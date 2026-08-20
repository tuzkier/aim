import SwiftUI

struct TimelineView: View {
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: TimelineStore
    let planStore: PlanStore
    let recordStore: RecordStore
    let openAgent: (AgentContext, String?) -> Void

    @State private var showingComposer = false
    @State private var showingPregnancySetup = false
    @State private var showsBackToToday = false
    @State private var toast: AimToastMessage?
    @State private var delayTarget: TaskItem?
    @State private var completedTaskID: UUID?
    @State private var recordPromptTask: TaskItem?

    private let todayAnchor = "timeline-today"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TimelineHeader(
                    week: store.currentWeek,
                    days: store.currentDays,
                    date: store.today,
                    filter: $store.filter,
                    onCompose: { if session.pregnancyID != nil { showingComposer = true } },
                    onAgent: { openAgent(agentContext, nil) }
                )
                Group {
                    if session.pregnancyID == nil {
                        setupPrompt
                    } else if store.weeks.isEmpty, store.isLoading {
                        ProgressView("正在整理孕期时间线")
                    } else if store.weeks.isEmpty, let message = store.errorMessage {
                        AimErrorState(message: message) { Task { await store.load() } }
                    } else {
                        timeline
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.aimCanvas)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.load() }
            .task(id: session.pregnancyID) {
                guard session.pregnancyID != nil, store.weeks.isEmpty else { return }
                await store.load()
            }
            .sheet(isPresented: $showingComposer) {
                RecordComposerView(store: recordStore) {
                    showingComposer = false
                    Task { await store.load() }
                }
            }
            .sheet(isPresented: $showingPregnancySetup) { PregnancySetupView() }
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
            .aimToast($toast)
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(store.weeks) { week in
                    Section {
                        rows(for: week)
                    } header: {
                        header(for: week)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.aimCanvas)
            .coordinateSpace(name: "timeline")
            .overlay(alignment: .bottom) {
                if showsBackToToday { backToToday(proxy) }
            }
            .task {
                proxy.scrollTo(todayAnchor, anchor: .top)
            }
            .onPreferenceChange(TodayOffsetKey.self) { offset in
                let threshold = UIScreen.main.bounds.height * 2
                let shouldShow = abs(offset) > threshold
                if shouldShow != showsBackToToday { showsBackToToday = shouldShow }
            }
            .sensoryFeedback(.success, trigger: completedTaskID)
        }
    }

    private func header(for week: TimelineWeek) -> some View {
        let isCurrent = week.position == .current
        return AimWeekHeader(week: week.week, startDate: week.startDate, endDate: week.endDate,
                              position: week.position, count: week.entries.count)
            .listRowInsets(EdgeInsets(top: 0, leading: AimMetrics.rowLeadingInset,
                                      bottom: 0, trailing: AimMetrics.space16))
            .listRowBackground(AimTimelineRail(position: week.position, showsDot: true))
            .id(isCurrent ? todayAnchor : "week-\(week.week)")
            .background {
                if isCurrent {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TodayOffsetKey.self,
                            value: proxy.frame(in: .named("timeline")).minY
                        )
                    }
                }
            }
    }

    @ViewBuilder
    private func rows(for week: TimelineWeek) -> some View {
        if store.isCollapsed(week) {
            Button { store.expand(week) } label: {
                HStack {
                    Text("孕 \(week.week) 周 · \(week.entries.count) 项")
                        .font(.footnote)
                        .foregroundStyle(Color.aimTextTertiary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.aimTextTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, AimMetrics.space8)
            .listRowInsets(EdgeInsets(top: 0, leading: AimMetrics.rowLeadingInset,
                                      bottom: 0, trailing: AimMetrics.space16))
            .listRowSeparator(.hidden)
            .listRowBackground(AimTimelineRail(position: week.position))
            .accessibilityIdentifier("timeline-week-collapsed-\(week.week)")
        } else {
            if week.position == .current, let focus = store.focusTask {
                AimFocusCard(task: focus) { openAgent(agentContext, nil) }
                    .listRowInsets(EdgeInsets(top: AimMetrics.space8, leading: AimMetrics.rowLeadingInset,
                                              bottom: AimMetrics.space12, trailing: AimMetrics.space16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(AimTimelineRail(position: week.position))
                    .accessibilityIdentifier("timeline-today-anchor")
            }

            ForEach(entries(in: week)) { entry in
                row(entry)
                    .listRowInsets(EdgeInsets(top: 0, leading: AimMetrics.rowLeadingInset,
                                              bottom: 0, trailing: AimMetrics.space16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(AimTimelineRail(position: week.position))
            }
        }
    }

    private func entries(in week: TimelineWeek) -> [TimelineEntry] {
        guard week.position == .current, let focus = store.focusTask else { return week.entries }
        return week.entries.filter { $0.id != TimelineEntry.task(focus).id }
    }

    @ViewBuilder
    private func row(_ entry: TimelineEntry) -> some View {
        switch entry {
        case let .task(task):
            NavigationLink {
                TaskDetailView(task: task, repository: planStore.repository)
            } label: {
                AimTaskRow(task: task, assigneeName: store.assigneeName(for: task.assignedMemberID))
            }
            .accessibilityIdentifier("timeline-task-row")
            .swipeActions(edge: .leading) {
                if task.isOpen {
                    Button {
                        Task {
                            if await store.complete(task) {
                                completedTaskID = task.id
                                toast = AimToastMessage(
                                    text: "已完成「\(task.title)」",
                                    undoTitle: "记一下",
                                    accessibilityIdentifier: "complete-task-record-prompt"
                                ) {
                                    recordPromptTask = task
                                }
                            }
                        }
                    } label: {
                        Label("完成", systemImage: "checkmark")
                    }
                    .tint(Color.aimSuccess)
                }
            }
            .swipeActions(edge: .trailing) {
                if task.isOpen {
                    Button {
                        delayTarget = task
                    } label: {
                        Label("延期", systemImage: "calendar")
                    }
                    .tint(Color.aimAccent)
                }
            }
        case let .record(record):
            NavigationLink {
                RecordDetailView(record: record, store: recordStore, planStore: planStore, openAgent: openAgent)
            } label: {
                AimRecordRow(record: record)
            }
            .accessibilityIdentifier("record-row-\(record.type.rawValue)")
        }
    }

    private func backToToday(_ proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation { proxy.scrollTo(todayAnchor, anchor: .top) }
        } label: {
            Label("回到今天", systemImage: "arrow.up.to.line")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, AimMetrics.space16)
                .padding(.vertical, AimMetrics.space8)
                .background(Color.aimSurfaceRaised, in: Capsule())
                .overlay { Capsule().stroke(Color.aimSeparator, lineWidth: 1) }
                .foregroundStyle(Color.aimAccent)
        }
        .padding(.bottom, AimMetrics.space12)
        .accessibilityIdentifier("timeline-back-to-today")
    }

    private var setupPrompt: some View {
        AimEmptyState(
            title: "先补充孕期信息",
            message: "有了预产期或末次月经，Aim 才能把计划和记录放进正确的孕周。",
            actionTitle: "补充孕期信息"
        ) { showingPregnancySetup = true }
    }

    private var agentContext: AgentContext {
        let week = store.currentWeek.map { "孕 \($0) 周" } ?? "孕期"
        var lines = [week]
        if let focus = store.focusTask { lines.append("当前最重要：" + focus.title) }
        return AgentContext(title: "孕期", summary: lines.joined(separator: "\n"))
    }
}

private struct TodayOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
