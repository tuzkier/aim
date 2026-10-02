import SwiftUI

/// 「孕期」Tab 的根：以今天为顶的总控页。
///
/// 之前首页就是整条时间线，今天夹在过去与未来中间，靠启动时 scrollTo 定位——
/// List 懒加载让这一跳经常静默失败，过去内容越多今天就越沉底。现在今天天然在顶部，
/// 完整时间线从标题 push 进去，过去的周在那边折叠。
struct HomeView: View {
    @Environment(AppSessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var store: TimelineStore
    let planStore: PlanStore
    let recordStore: RecordStore
    let agentStore: AgentStore

    @State private var showingTimeline = false
    @State private var showingTaskComposer = false
    @State private var showingRecordComposer = false
    @State private var showingAgent = false
    @State private var toast: AimToastMessage?
    @State private var delayTarget: TaskItem?
    @State private var recordPromptTask: TaskItem?
    @State private var focusDetailTask: TaskItem?
    @State private var pendingTaskIDs: Set<UUID> = []
    @State private var completedTaskID: UUID?

    @State private var isQuickAdding = false
    @State private var quickAddText = ""
    @State private var isQuickAddSubmitting = false
    @State private var quickAddError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HomeHeader(
                    week: store.currentWeek,
                    days: store.currentDays,
                    date: store.today,
                    stageName: store.stageName,
                    onOpenTimeline: { showingTimeline = true },
                    onNewTask: { showingTaskComposer = true },
                    onNewRecord: { if session.pregnancyID != nil { showingRecordComposer = true } },
                    onAgent: {
                        // 首页的 AIM 按钮不针对某一页，开一段普通的新对话，不带上下文标签。
                        agentStore.focus(context: nil)
                        showingAgent = true
                    }
                )
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.aimCanvas)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: session.pregnancyID) {
                guard session.pregnancyID != nil, store.weeks.isEmpty else { return }
                await store.load()
            }
            .onAppear {
                if let notice = session.welcomeBackNotice {
                    toast = AimToastMessage(text: notice, undoTitle: "", accessibilityIdentifier: "home-welcome-back")
                    session.welcomeBackNotice = nil
                } else if let notice = session.familyNotice {
                    toast = AimToastMessage(text: notice, undoTitle: "", accessibilityIdentifier: "home-family-notice")
                    session.familyNotice = nil
                }
            }
            // `store.now` 只在 load() 里刷新。App 在后台放一夜再回来，「今天」「逾期」「接下来 7 天」
            // 都还按昨天分组。回到前台先把 now 拨到现在——store 是 @Observable，各分组随之重算；
            // 若日历日已经变了，孕周和服务端 as_of 也过期了，再整页重拉一次。
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                let calendar = PregnancyDateCalculator.calendar
                let dayChanged = calendar.startOfDay(for: store.now) != calendar.startOfDay(for: .now)
                store.now = .now
                if dayChanged, session.pregnancyID != nil {
                    Task { await store.load() }
                }
            }
            .navigationDestination(isPresented: $showingTimeline) {
                TimelineView(store: store, planStore: planStore, recordStore: recordStore, agentStore: agentStore)
            }
            .navigationDestination(item: $focusDetailTask) { task in
                TaskDetailView(task: task, repository: planStore.repository)
            }
            .sheet(isPresented: $showingTaskComposer) {
                TaskComposerView(members: store.familyMembers, now: .now) { draft in
                    let ok = await store.createTask(
                        title: draft.title, description: draft.detail,
                        dueAt: draft.dueAt, assignedMemberID: draft.assignedMemberID)
                    return ok ? nil : (store.errorMessage ?? "没能保存这条待办，稍后再试。")
                }
            }
            .sheet(isPresented: $showingRecordComposer) {
                RecordComposerView(store: recordStore) {
                    showingRecordComposer = false
                    Task { await store.load() }
                }
            }
            .sheet(item: $delayTarget) { task in
                TaskDelaySheet(task: task, repository: planStore.repository) { _ in
                    delayTarget = nil
                    Task { await store.load() }
                }
            }
            .sheet(item: $recordPromptTask) { task in
                RecordComposerView(
                    store: recordStore,
                    suggestedType: TaskRecordSuggestion.recordType(forTaskTitle: task.title),
                    suggestedText: task.title
                ) {
                    recordPromptTask = nil
                    Task { await store.load() }
                }
            }
            .fullScreenCover(isPresented: $showingAgent) {
                AgentView(store: agentStore) { showingAgent = false }
            }
            .aimToast($toast)
            .sensoryFeedback(.success, trigger: completedTaskID)
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if store.weeks.isEmpty, store.isLoading {
            ProgressView("正在整理今天")
        } else if store.weeks.isEmpty, let message = store.errorMessage {
            AimErrorState(message: message) { Task { await store.load() } }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if let focus = store.focusTask {
                AimFocusCard(task: focus) { focusDetailTask = focus }
                    .listRowInsets(EdgeInsets(top: AimMetrics.space8, leading: AimMetrics.space20,
                                              bottom: AimMetrics.space12, trailing: AimMetrics.space20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.aimCanvas)
                    .accessibilityIdentifier("home-focus-card")
            }

            Section {
                sectionHeader("今天 · \(store.todayTasks.count) 项", trailing: overdueBadge)
                if store.todayTasks.isEmpty {
                    quietRow("今天没有安排")
                }
                ForEach(store.todayTasks) { task in
                    taskRow(task, style: .due)
                }
                TaskQuickAddRow(
                    isEditing: $isQuickAdding,
                    text: $quickAddText,
                    isSubmitting: isQuickAddSubmitting,
                    errorMessage: quickAddError,
                    onSubmit: { Task { await submitQuickAdd() } }
                )
                .listRowInsets(rowInsets)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.aimCanvas)
            }

            if !store.upcomingTasks.isEmpty {
                Section {
                    sectionHeader("接下来 7 天")
                    ForEach(store.upcomingTasks.prefix(5)) { task in
                        taskRow(task, style: .upcoming)
                    }
                    if store.upcomingTasks.count > 5 {
                        linkRow("还有 \(store.upcomingTasks.count - 5) 项 · 查看时间线")
                    }
                }
            }

            Section {
                sectionHeader("最近记录", trailing: AnyView(
                    Button("全部") { showingTimeline = true }
                        .font(.caption2)
                        .foregroundStyle(Color.aimAccent)
                        .buttonStyle(.plain)
                ))
                if store.recentRecords.isEmpty {
                    quietRow("还没有记录")
                }
                ForEach(store.recentRecords) { record in
                    NavigationLink {
                        RecordDetailView(record: record, store: recordStore, planStore: planStore, agentStore: agentStore)
                    } label: {
                        AimRecordRow(record: record)
                    }
                    .listRowInsets(rowInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.aimCanvas)
                    .accessibilityIdentifier("record-row-\(record.type.rawValue)")
                }
            }

            Section {
                linkRow("查看完整时间线")
                    .accessibilityIdentifier("home-open-timeline")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.aimCanvas)
        .refreshable { await store.load() }
        .safeAreaPadding(.bottom, AimMetrics.space28)
        // 快速添加行收起时把上次的错误一并清掉，下次展开不该还挂着旧提示。
        .onChange(of: isQuickAdding) { _, editing in
            if !editing { quickAddError = nil }
        }
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: AimMetrics.space20, bottom: 0, trailing: AimMetrics.space20)
    }

    private var overdueBadge: AnyView? {
        guard store.overdueCount > 0 else { return nil }
        return AnyView(
            Text("逾期 \(store.overdueCount)")
                .font(.caption2)
                .foregroundStyle(Color.aimDanger)
        )
    }

    private func sectionHeader(_ title: String, trailing: AnyView? = nil) -> some View {
        HStack {
            Text(title).aimLabelStyle()
            Spacer()
            if let trailing { trailing }
        }
        .padding(.top, AimMetrics.space16)
        .padding(.bottom, AimMetrics.space4)
        .listRowInsets(rowInsets)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.aimCanvas)
        .accessibilityAddTraits(.isHeader)
    }

    private func quietRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.aimTextTertiary)
            .padding(.vertical, AimMetrics.space8)
            .listRowInsets(rowInsets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.aimCanvas)
    }

    private func linkRow(_ text: String) -> some View {
        Button { showingTimeline = true } label: {
            HStack(spacing: AimMetrics.space4) {
                Text(text).font(.subheadline.weight(.medium))
                Image(systemName: "arrow.right").font(.footnote)
            }
            .foregroundStyle(Color.aimAccent)
            .padding(.vertical, AimMetrics.space8)
        }
        .buttonStyle(.plain)
        .listRowInsets(rowInsets)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.aimCanvas)
    }

    private func taskRow(_ task: TaskItem, style: AimTaskRow.Style) -> some View {
        NavigationLink {
            TaskDetailView(task: task, repository: planStore.repository)
        } label: {
            AimTaskRow(
                task: task,
                assigneeName: store.assigneeName(for: task.assignedMemberID),
                now: store.now,
                isOverdue: store.isOverdue(task),
                isPending: pendingTaskIDs.contains(task.id),
                style: style
            ) {
                Task { await complete(task) }
            }
        }
        .listRowInsets(rowInsets)
        .listRowSeparator(.visible)
        .listRowSeparatorTint(Color.aimSeparator)
        .listRowBackground(Color.aimCanvas)
        .accessibilityIdentifier("home-task-row")
        .swipeActions(edge: .leading) {
            Button {
                Task { await complete(task) }
            } label: {
                Label("完成", systemImage: "checkmark")
            }
            .tint(Color.aimSuccess)
        }
        .swipeActions(edge: .trailing) {
            Button {
                delayTarget = task
            } label: {
                Label("延期", systemImage: "calendar")
            }
            .tint(Color.aimAccent)
        }
    }

    // MARK: - 动作

    private func complete(_ task: TaskItem) async {
        // 按任务记录请求中状态：连点两行各自转圈，互不拦截。并发的 complete 各自 reload，
        // 拉回的是同一份数据，后到的覆盖先到的也无妨。
        guard !pendingTaskIDs.contains(task.id) else { return }
        pendingTaskIDs.insert(task.id)
        defer { pendingTaskIDs.remove(task.id) }
        if await store.complete(task) {
            completedTaskID = task.id
            toast = AimToastMessage(
                text: "已完成「\(task.title)」",
                undoTitle: "记一下",
                accessibilityIdentifier: "complete-task-record-prompt"
            ) {
                recordPromptTask = task
            }
        } else {
            toast = AimToastMessage(
                text: store.errorMessage ?? "没能标记完成，稍后再试。",
                undoTitle: "",
                accessibilityIdentifier: "home-complete-failed",
                style: .failure
            )
        }
    }

    private func submitQuickAdd() async {
        let title = quickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            isQuickAdding = false
            return
        }
        isQuickAddSubmitting = true
        quickAddError = nil
        defer { isQuickAddSubmitting = false }
        if await store.createTask(title: title, dueAt: TaskDateText.endOfDay(.now)) {
            // 请求期间输入框没有禁用，用户可能已经在打下一条；只有内容还是刚提交的那条才清空。
            if quickAddText.trimmingCharacters(in: .whitespacesAndNewlines) == title {
                quickAddText = ""
            }
        } else {
            quickAddError = store.errorMessage ?? "没能保存这条待办，稍后再试。"
        }
    }
}
