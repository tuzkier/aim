import SwiftUI

@main
struct AimApp: App {
    @State private var session = AppSessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(.aimAccent)
        }
    }
}

private struct RootView: View {
    @Environment(AppSessionStore.self) private var session

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
    }
}

private struct MainTabView: View {
    @Environment(AppSessionStore.self) private var session
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
            Task { await reloadRepositories() }
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
        timelineStore.repository = repository
        planStore.repository = repository
        recordStore.repository = repository
        familyStore.repository = repository
        homeStore.repository = repository
        // Agent 撤销「新建」类操作要直接调删除接口，不经过模型。
        agentStore.repository = repository
        agentStore.sessions = agentSessions
        libraryStore.repository = repository
        await timelineStore.load()
        await planStore.load()
        await recordStore.load()
        await familyStore.load()
        await libraryStore.load()
        await homeStore.load()
        await invitationPrompt.check(using: repository)
    }
}
