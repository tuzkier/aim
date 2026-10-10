import SwiftUI

/// 胎动页：今天、最近 14 天趋势、历史。
struct FetalMovementView: View {
    @Environment(FetalMovementStore.self) private var store
    let agentStore: AgentStore

    @State private var counting = false
    @State private var showingAgent = false
    @State private var showingGuide = false

    var body: some View {
        List {
            Section {
                todayRow
                if let unfinished = store.unfinishedActive {
                    Button { counting = true } label: {
                        Label(FetalMovementCopy.resume(count: unfinished.count) + " · 继续", systemImage: "hand.tap")
                    }
                    .accessibilityIdentifier("fetal-movement-resume")
                } else {
                    Button { counting = true } label: {
                        Label("开始数胎动", systemImage: "hand.tap")
                    }
                    .accessibilityIdentifier("fetal-movement-start")
                }
                Button("怎么数？") { showingGuide = true }
                    .accessibilityIdentifier("fetal-movement-guide")
                FetalMovementRetryButton()
            }
            Section("最近 14 天 · 数到 10 次的用时") {
                FetalMovementTrendBars(days: FetalMovementInsights.dailyTrend(store.sessions, now: store.clock()))
            }
            ForEach(groupedByDay, id: \.day) { group in
                Section(group.day.formatted(.dateTime.month().day().weekday())) {
                    ForEach(group.sessions) { session in
                        HStack {
                            Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(Color.aimTextSecondary)
                            Text(FetalMovementFormat.summary(session.data))
                                .foregroundStyle(session.data.outcome == .under || session.data.reportedLess
                                                 ? Color.aimDanger : Color.aimTextPrimary)
                        }
                        .swipeActions {
                            Button(role: .destructive) { Task { await store.delete(session) } } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            Section {
                Text(FetalMovementCopy.mostImportant).font(.footnote).foregroundStyle(Color.aimDanger)
            }
        }
        .navigationTitle("胎动")
        .accessibilityIdentifier("fetal-movement-page")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    agentStore.prepareAnalysis("帮我看看最近的胎动记录", context: AgentContext(title: "胎动", summary: recentSummary))
                    showingAgent = true
                } label: { Image(systemName: "wand.and.sparkles") }
            }
        }
        .task {
            // 被系统杀掉后过期的断点先记为未数完，再拉历史，列表里才能看到它。
            await store.settleExpiredActive()
            await store.load()
        }
        .refreshable { await store.load() }
        .fullScreenCover(isPresented: $counting) {
            FetalMovementCounterView(agentStore: agentStore) { counting = false }
        }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
        .sheet(isPresented: $showingGuide) { FetalMovementGuideView() }
    }

    private var todayRow: some View {
        Text(store.today.map { "今天 " + FetalMovementFormat.summary($0.data) } ?? "今天还没数")
            .font(.headline)
    }

    private var recentSummary: String {
        let week = store.sessions.prefix(7).map {
            $0.startedAt.formatted(date: .abbreviated, time: .shortened) + " " + FetalMovementFormat.summary($0.data)
        }
        return week.isEmpty ? "还没有胎动记录" : "最近的胎动记录：\n" + week.joined(separator: "\n")
    }

    private var groupedByDay: [(day: Date, sessions: [FetalMovementSession])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: store.sessions) { calendar.startOfDay(for: $0.startedAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }
}

/// 14 根柱子：高度是当天第一次数到 10 次的用时；当天有「不足 10 次」的标红点。
struct FetalMovementTrendBars: View {
    let days: [FetalMovementDay]

    /// 柱子本身对读屏没有意义，合成一句话读出来。
    private var accessibilitySummary: String {
        let reached = days.filter { $0.reachedSeconds != nil }.count
        let under = days.filter(\.hadUnder).count
        return "最近 \(days.count) 天中 \(reached) 天数完，\(under) 天不足 10 次"
    }

    var body: some View {
        let longest = max(days.compactMap(\.reachedSeconds).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(days, id: \.date) { day in
                VStack(spacing: 2) {
                    if day.hadUnder { Circle().fill(Color.aimDanger).frame(width: 6, height: 6) }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(day.reachedSeconds == nil ? Color.aimSurfaceSunken : Color.aimAccent)
                        .frame(height: day.reachedSeconds.map { 8 + CGFloat($0) / CGFloat(longest) * 60 } ?? 4)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 80, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }
}

/// 首页「数胎动」卡。孕 28 周起由首页决定是否显示。
struct FetalMovementHomeCard: View {
    @Environment(FetalMovementStore.self) private var store
    let agentStore: AgentStore
    @State private var counting = false

    private var subtitle: String {
        if let unfinished = store.unfinishedActive { return FetalMovementCopy.resume(count: unfinished.count) }
        return store.today.map { "今天 " + FetalMovementFormat.summary($0.data) } ?? "今天还没数"
    }

    var body: some View {
        // 「开始」不能放进 NavigationLink 的 label 里——链接会吞掉内层按钮的点击。
        HStack {
            NavigationLink {
                FetalMovementView(agentStore: agentStore)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: AimMetrics.space4) {
                        Text("数胎动").font(.headline).foregroundStyle(Color.aimTextPrimary)
                        Text(subtitle).font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-fetal-movement-card")
            if store.unfinishedActive != nil {
                Button("继续") { counting = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("fetal-movement-resume")
            } else {
                Button("开始") { counting = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("home-fetal-movement-start")
            }
        }
        .aimCard()
        .task {
            await store.settleExpiredActive()
            await store.load()
        }
        .fullScreenCover(isPresented: $counting) {
            FetalMovementCounterView(agentStore: agentStore) { counting = false }
        }
    }
}
