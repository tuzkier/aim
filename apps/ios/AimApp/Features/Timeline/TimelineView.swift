import SwiftUI

/// 完整的孕期时间线，从首页标题 push 进来。
///
/// 过去的周折叠在顶部一行里，今天所在周因此天然是第一个分组——不再需要启动时
/// `scrollTo`，那一跳在 List 懒加载下并不可靠。「回到今天」只在展开过去周后出现，
/// 点击即收起，今天就回到顶部；随后的 `scrollTo` 失败也无碍。
struct TimelineView: View {
    @Bindable var store: TimelineStore
    let planStore: PlanStore
    let recordStore: RecordStore
    let agentStore: AgentStore

    @State private var toast: AimToastMessage?
    @State private var delayTarget: TaskItem?
    @State private var completedTaskID: UUID?
    @State private var recordPromptTask: TaskItem?

    private let todayAnchor = "timeline-today"

    var body: some View {
        Group {
            if store.weeks.isEmpty, store.isLoading {
                ProgressView("正在整理孕期时间线")
            } else if store.weeks.isEmpty, let message = store.errorMessage {
                AimErrorState(message: message) { Task { await store.load() } }
            } else {
                timeline
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.aimCanvas)
        .navigationTitle("孕期时间线")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("筛选", selection: $store.filter) {
                        ForEach(TimelineFilter.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(store.filter == .all ? Color.aimTextSecondary : Color.aimAccent)
                }
                .accessibilityLabel("筛选")
                .accessibilityIdentifier("timeline-filter")
            }
        }
        .refreshable { await store.load() }
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
        .sensoryFeedback(.success, trigger: completedTaskID)
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            List {
                if !store.pastWeeks.isEmpty {
                    Section {
                        pastToggleRow
                    }
                    if store.isPastExpanded {
                        ForEach(store.pastWeeks) { week in
                            Section {
                                rows(for: week)
                            } header: {
                                header(for: week)
                            }
                        }
                    }
                }
                ForEach(store.weeks.filter { $0.position != .past }) { week in
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
            .overlay(alignment: .bottom) {
                if store.isPastExpanded { backToToday(proxy) }
            }
        }
    }

    private var pastToggleRow: some View {
        Button {
            withAnimation(.snappy) { store.isPastExpanded.toggle() }
        } label: {
            HStack {
                Text(pastSummary)
                    .font(.footnote)
                    .foregroundStyle(Color.aimTextSecondary)
                Spacer()
                Image(systemName: store.isPastExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.aimTextTertiary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, AimMetrics.space8)
        .listRowInsets(EdgeInsets(top: 0, leading: AimMetrics.rowLeadingInset,
                                  bottom: 0, trailing: AimMetrics.space16))
        .listRowSeparator(.hidden)
        .listRowBackground(AimTimelineRail(position: .past))
        .accessibilityIdentifier("timeline-past-collapsed")
    }

    private var pastSummary: String {
        let past = store.pastWeeks
        guard let first = past.first?.week, let last = past.last?.week else { return "之前" }
        let count = past.reduce(0) { $0 + $1.entries.count }
        let range = first == last ? "孕 \(first) 周" : "孕 \(first)–\(last) 周"
        return "之前 · \(range) · \(count) 项"
    }

    private func header(for week: TimelineWeek) -> some View {
        let isCurrent = week.position == .current
        return AimWeekHeader(week: week.week, startDate: week.startDate, endDate: week.endDate,
                              position: week.position, count: week.entries.count)
            .listRowInsets(EdgeInsets(top: 0, leading: AimMetrics.rowLeadingInset,
                                      bottom: 0, trailing: AimMetrics.space16))
            .listRowBackground(AimTimelineRail(position: week.position, showsDot: true))
            .id(isCurrent ? todayAnchor : "week-\(week.week)")
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
            ForEach(week.entries) { entry in
                row(entry)
                    .listRowInsets(EdgeInsets(top: 0, leading: AimMetrics.rowLeadingInset,
                                              bottom: 0, trailing: AimMetrics.space16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(AimTimelineRail(position: week.position))
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: TimelineEntry) -> some View {
        switch entry {
        case let .task(task):
            NavigationLink {
                TaskDetailView(task: task, repository: planStore.repository)
            } label: {
                AimTaskRow(
                    task: task,
                    assigneeName: store.assigneeName(for: task.assignedMemberID),
                    now: store.now,
                    isOverdue: task.isOpen && store.isOverdue(task)
                )
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
                RecordDetailView(record: record, store: recordStore, planStore: planStore, agentStore: agentStore)
            } label: {
                AimRecordRow(record: record)
            }
            .accessibilityIdentifier("record-row-\(record.type.rawValue)")
        }
    }

    private func backToToday(_ proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.snappy) { store.isPastExpanded = false }
            proxy.scrollTo(todayAnchor, anchor: .top)
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
}
