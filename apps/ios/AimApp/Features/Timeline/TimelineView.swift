import SwiftUI

struct TimelineView: View {
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: TimelineStore
    let planStore: PlanStore
    let recordStore: RecordStore

    @State private var showingComposer = false
    @State private var showingAgent = false
    @State private var showingPregnancySetup = false
    @State private var showsBackToToday = false

    private let todayAnchor = "timeline-today"

    var body: some View {
        NavigationStack {
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
            .background(Color.aimCanvas)
            .navigationTitle(navigationTitle)
            .toolbar { toolbar }
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
            .fullScreenCover(isPresented: $showingAgent) {
                AgentSheet(context: agentContext)
            }
        }
    }

    private var navigationTitle: String {
        guard let week = store.currentWeek else { return "孕期" }
        return "孕 \(week) 周"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("筛选", selection: $store.filter) {
                    ForEach(TimelineFilter.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .accessibilityIdentifier("timeline-filter")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("新增记录", systemImage: "plus") { showingComposer = true }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("问一问", systemImage: "wand.and.sparkles") { showingAgent = true }
                .accessibilityIdentifier("global-agent-button")
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(store.weeks) { week in
                    Section {
                        rows(for: week)
                    } header: {
                        AimWeekHeader(week: week.week, startDate: week.startDate, endDate: week.endDate,
                                      position: week.position, count: week.entries.count)
                            .listRowInsets(EdgeInsets(top: 0, leading: AimMetrics.rowLeadingInset,
                                                      bottom: 0, trailing: AimMetrics.space16))
                            .listRowBackground(AimTimelineRail(position: week.position, showsDot: true))
                            .id(week.position == .current ? todayAnchor : "week-\(week.week)")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.aimCanvas)
            .safeAreaInset(edge: .bottom) {
                if showsBackToToday { backToToday(proxy) }
            }
            .task {
                proxy.scrollTo(todayAnchor, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func rows(for week: TimelineWeek) -> some View {
        if week.position == .current, let focus = store.focusTask {
            AimFocusCard(task: focus) { showingAgent = true }
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
        case let .record(record):
            NavigationLink {
                RecordDetailView(record: record, store: recordStore, planStore: planStore)
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
