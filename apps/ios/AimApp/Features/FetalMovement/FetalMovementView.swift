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
                Button { counting = true } label: {
                    Label("开始数胎动", systemImage: "hand.tap")
                }
                .accessibilityIdentifier("fetal-movement-start")
                Button("怎么数？") { showingGuide = true }
                    .accessibilityIdentifier("fetal-movement-guide")
                if !store.unsaved.isEmpty {
                    Button("有一次没保存上，重试") { Task { await store.saveUnsaved() } }
                        .accessibilityIdentifier("fetal-movement-retry")
                }
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
                                .foregroundStyle(session.data.outcome == .under ? Color.aimDanger : Color.aimTextPrimary)
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
        .task { await store.load() }
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
        .accessibilityLabel("最近 14 天数胎动用时")
    }
}

/// 首页「数胎动」卡。孕 28 周起由首页决定是否显示。
struct FetalMovementHomeCard: View {
    @Environment(FetalMovementStore.self) private var store
    let agentStore: AgentStore
    @State private var counting = false

    var body: some View {
        // 「开始」不能放进 NavigationLink 的 label 里——链接会吞掉内层按钮的点击。
        HStack {
            NavigationLink {
                FetalMovementView(agentStore: agentStore)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: AimMetrics.space4) {
                        Text("数胎动").font(.headline).foregroundStyle(Color.aimTextPrimary)
                        Text(store.today.map { "今天 " + FetalMovementFormat.summary($0.data) } ?? "今天还没数")
                            .font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-fetal-movement-card")
            Button("开始") { counting = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("home-fetal-movement-start")
        }
        .aimCard()
        .task { await store.load() }
        .fullScreenCover(isPresented: $counting) {
            FetalMovementCounterView(agentStore: agentStore) { counting = false }
        }
    }
}
