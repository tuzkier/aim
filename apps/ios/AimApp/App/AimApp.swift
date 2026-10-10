import SwiftUI

@main
struct AimApp: App {
    @UIApplicationDelegateAdaptor(ReminderAppDelegate.self) private var reminderDelegate
    @State private var session = AppSessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(ReminderCoordinator.shared)
                .tint(.aimAccent)
        }
    }
}

private struct RootView: View {
    @Environment(AppSessionStore.self) private var session
    @Environment(ReminderCoordinator.self) private var reminders

    var body: some View {
        Group {
            if !session.isConfigured {
                OnboardingView()
            } else if session.pregnancyID == nil {
                // 没有孕期档案就没有孕周，计划和记录都无处安放。
                // 这里是准入门槛，不是可跳过的提示。
                PregnancySetupView()
            } else {
                MainTabView()
            }
        }
        .task { reminders.bind(ReminderScope(session: session)) }
    }
}

private struct MainTabView: View {
    @Environment(AppSessionStore.self) private var session
    @Environment(ReminderCoordinator.self) private var reminders
    @Environment(\.scenePhase) private var scenePhase
    @State private var reminderPresentation: ReminderPresentation?
    @State private var timelineStore = TimelineStore()
    @State private var planStore = PlanStore()
    @State private var recordStore = RecordStore()
    @State private var familyStore = FamilyStore()
    @State private var agentStore = AgentStore()
    @State private var agentSessions = AgentSessionStore()
    @State private var libraryStore = LibraryStore()
    @State private var agentDestinations: AgentDestinations?
    @State private var refreshCoalescer: AgentRefreshCoalescer?
    @State private var homeStore = HomeDashboardStore()
    @State private var selectedTab: MainTab = .home
    @State private var invitationPrompt = InvitationPromptStore()
    /// UI 测试要在一秒内连点 10 次，用启动参数关掉防误触去重。
    @State private var fetalMovementStore = FetalMovementStore(
        dedupeInterval: ProcessInfo.processInfo.arguments.contains("-fetal-dedupe-zero")
            ? 0 : FetalMovementCounter.defaultDedupeInterval)

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView(
                store: homeStore,
                recordStore: recordStore,
                familyStore: familyStore,
                libraryStore: libraryStore,
                agentStore: agentStore,
                onSwitchTab: { selectedTab = $0 }
            )
                .tabItem { Label("首页", systemImage: "house") }
                .tag(MainTab.home)
            HomeView(store: timelineStore, planStore: planStore, recordStore: recordStore, agentStore: agentStore)
                .tabItem { Label("待办", systemImage: "checklist") }
                .tag(MainTab.tasks)


            AgentView(store: agentStore)
                .tabItem { Label("AIM", systemImage: "wand.and.sparkles") }
                .tag(MainTab.agent)
            LibraryView(store: libraryStore, agentStore: agentStore)
                .tabItem { Label("资料库", systemImage: "books.vertical") }
                .tag(MainTab.library)

            FamilyView(store: familyStore)
                .tabItem { Label("家庭", systemImage: "person.2") }
                .tag(MainTab.family)
        }
        .environment(agentDestinations)
        .environment(fetalMovementStore)
        .onAppear {
            if refreshCoalescer == nil {
                refreshCoalescer = AgentRefreshCoalescer { kinds in await refresh(after: kinds) }
            }
            if agentDestinations == nil {
                agentDestinations = AgentDestinations(
                    planStore: planStore,
                    recordStore: recordStore,
                    libraryStore: libraryStore,
                    agentStore: agentStore
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aimDataChanged)) { note in
            let kinds = Set(note.userInfo?["kinds"] as? [String] ?? ["task", "record", "knowledge"])
            Task { await refreshCoalescer?.request(kinds) }
        }
        .task { await reloadRepositories() }
        .onChange(of: session.pregnancyID) { _, _ in
            Task { await reloadRepositories() }
        }
        .onChange(of: session.familyID) { _, _ in
            reminderPresentation = nil
            Task { await reloadRepositories() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reminders.refresh(activeCount: fetalMovementStore.active?.startedAt) } }
        }
        .onChange(of: fetalMovementStore.active) { _, value in
            Task { await reminders.refresh(activeCount: value?.startedAt) }
        }
        .onChange(of: reminders.pendingRoute) { _, _ in Task { await openReminder() } }
        .sheet(item: $reminderPresentation) { target in
            NavigationStack {
                Group {
                    switch target {
                    case let .task(task): TaskDetailView(task: task, repository: planStore.repository)
                    case .fetal: FetalMovementView(agentStore: agentStore)
                    case .weekly:
                        if let repository = planStore.repository { WeeklyBriefView(repository: repository) }
                    case .unavailable: Text("这条提醒已更新，请查看当前安排。")
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { reminderPresentation = nil }.accessibilityIdentifier("reminder-close")
                    }
                }
            }
        }
        // 家人发来的邀请：进入主界面时查一次，没「暂不」过的逐条弹出。
        .sheet(item: Binding(
            get: { invitationPrompt.current },
            set: { if $0 == nil { invitationPrompt.current = nil } }
        )) { invitation in
            InvitationDecisionSheet(invitation: invitation, repository: familyStore.repository) {
                if let repository = familyStore.repository {
                    Task { await invitationPrompt.next(using: repository) }
                }
            }
        }
        // 被管理员移出：家庭接口开始返回 403。找回自己的新家庭并切过去。
        .onChange(of: familyStore.lostMembership) { _, lost in
            guard lost, let repository = familyStore.repository else { return }
            Task { await recoverFromRemoval(using: repository) }
        }
    }

    private func recoverFromRemoval(using repository: BusinessRepositoryProtocol) async {
        let oldName = familyStore.snapshot?.name
        guard let me = try? await repository.fetchMe(), me.familyID != session.familyID else { return }
        familyStore.lostMembership = false
        session.familyNotice = oldName.map { "你已不在「\($0)」里" } ?? "你已不在原来的家庭里"
        session.switchFamily(familyID: me.familyID, pregnancyID: me.pregnancyID)
    }

    /// AIM 写过东西之后只刷新受影响的页面。首页同时显示待办和最近记录，两类都要刷它。
    private func refresh(after kinds: Set<String>) async {
        if kinds.contains("task") {
            await planStore.load()
        }
        if kinds.contains("record") {
            await recordStore.load()
        }
        if kinds.contains("task") || kinds.contains("record") {
            await timelineStore.load()
        }
        if kinds.contains("record") || kinds.contains("knowledge") {
            await libraryStore.load()
        }
    }


    private func reloadRepositories() async {
        let repository = BusinessRepository(environment: session.environment)
        reminders.bind(ReminderScope(session: session), repository: repository)
        reminders.setRepository(repository)
        timelineStore.repository = repository
        planStore.repository = repository
        recordStore.repository = repository
        familyStore.repository = repository
        homeStore.repository = repository
        // Agent 撤销「新建」类操作要直接调删除接口，不经过模型。
        agentStore.repository = repository
        agentStore.sessions = agentSessions
        libraryStore.repository = repository
        // 胎动计数的本地断点按「账号 + 孕期」分开存；还没有孕期时解绑，免得接着写别家的断点。
        // unbind() 会清掉仓库，所以每次绑定前都要重新设置。
        fetalMovementStore.repository = repository
        let fetalMovementBound: Bool
        if let accountID = session.accountID, let pregnancyID = session.pregnancyID {
            fetalMovementStore.bind(accountID: accountID, pregnancyID: pregnancyID)
            fetalMovementBound = true
        } else {
            fetalMovementStore.unbind()
            fetalMovementBound = false
        }
        await timelineStore.load()
        await planStore.load()
        await recordStore.load()
        await familyStore.load()
        await libraryStore.load()
        await homeStore.load()
        await invitationPrompt.check(using: repository)
        // 胎动排在最后：首页、待办等主数据先出来，不被胎动的保存与拉取拖慢。
        // 被系统杀掉后过期的断点先记为未数完并保存，再拉历史。
        if fetalMovementBound {
            await fetalMovementStore.settleExpiredActive()
            await fetalMovementStore.load()
        }
        await reminders.refresh(activeCount: fetalMovementStore.active?.startedAt)
        await openReminder()
    }

    private func openReminder() async {
        guard let pending = reminders.pendingRoute else { return }
        let route = pending.route
        guard route.scope == ReminderScope(session: session) else { reminders.pendingRoute = nil; return }
        // 冷启动时 delegate 可能先于仓储初始化到达；保留到 reloadRepositories 完成再消费。
        guard let repository = planStore.repository else { return }
        reminders.pendingRoute = nil
        switch route.kind {
        case .task:
            let plan = try? await repository.fetchPlan()
            guard route.scope == ReminderScope(session: session) else { return }
            selectedTab = .tasks
            if let task = plan?.tasks.first(where: { $0.id == route.taskID }) {
                reminderPresentation = .task(task)
            } else { reminderPresentation = .unavailable }
        case .fetalMovement: selectedTab = .library; reminderPresentation = .fetal
        case .weekly: selectedTab = .home; reminderPresentation = .weekly
        }
    }
}

private enum ReminderPresentation: Identifiable {
    case task(TaskItem), fetal, weekly, unavailable
    var id: String {
        switch self {
        case let .task(task): "task-\(task.id)"
        case .fetal: "fetal"
        case .weekly: "weekly"
        case .unavailable: "unavailable"
        }
    }
}
