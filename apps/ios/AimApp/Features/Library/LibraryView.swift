import SwiftUI

/// 资料库：孕期信息的统一入口。
///
/// 刻意不是列表。每张分类卡承载活数据（近 7 天几条、几次产检、反复出现的症状），
/// 扫一眼就知道哪里有新东西。分类本身来自 `LibraryCatalog`，加分类是加数据不是改这里。
struct LibraryView: View {
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: LibraryStore
    let agentStore: AgentStore

    @State private var showingAgent = false
    @State private var openCategory: LibraryCategoryID?
    @State private var openTopic: EncyclopediaTopic?
    @State private var openEntryID: String?
    @State private var openReportID: UUID?
    @Environment(AgentDestinations.self) private var destinations: AgentDestinations?

    private let columns = [
        GridItem(.flexible(), spacing: AimMetrics.space12),
        GridItem(.flexible(), spacing: AimMetrics.space12),
    ]

    /// 胎动卡 28 周起显示；更早但已经有胎动记录的（比如改过预产期）也显示。
    private var visibleGridCategories: [LibraryCategory] {
        LibraryCatalog.gridCategories.filter { category in
            guard category.id == .fetalMovement else { return true }
            return (store.currentWeek ?? 0) >= 28
                || store.snapshot.records.contains { $0.type == .fetalMovement }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AimMetrics.space12) {
                    header
                    // 立即就医级别的提示放在最前，不能让它排在「这周读什么」后面。
                    let focus = LibraryFocus.make(from: store.snapshot)
                    if let focus, focus.level == .urgent {
                        LibraryFocusBanner(focus: focus)
                    }
                    if let week = store.currentWeek {
                        let picks = store.encyclopedia.picks(forWeek: week)
                        if !picks.isEmpty {
                            EncyclopediaWeeklyPicks(
                                week: week, picks: picks, topics: store.encyclopedia.topics
                            ) { openEntryID = $0.id }
                        }
                    }
                    if let focus, focus.level != .urgent {
                        if let reportID = focus.reportID {
                            // 报告异常的提醒点进去就是那份报告，异常项和「加入想问医生」都在那里。
                            Button { openReportID = reportID } label: { LibraryFocusBanner(focus: focus) }
                                .buttonStyle(.plain)
                        } else {
                            LibraryFocusBanner(focus: focus)
                        }
                    }
                    sectionTitle("我的档案", identifier: "library-section-archive")
                    LazyVGrid(columns: columns, spacing: AimMetrics.space12) {
                        ForEach(visibleGridCategories) { category in
                            Button { openCategory = category.id } label: {
                                LibraryCategoryCard(
                                    category: category,
                                    summary: category.id.summary(from: store.snapshot),
                                    trend: category.id == .checkups
                                        ? MetricTrend.weight(from: store.snapshot.records)
                                        : nil
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("library-card-\(category.id.rawValue)")
                        }
                    }
                    if !store.encyclopedia.isEmpty {
                        sectionTitle("孕期百科", identifier: "library-section-encyclopedia")
                        EncyclopediaTopicGrid(catalog: store.encyclopedia, week: store.currentWeek) {
                            openTopic = $0
                        }
                    }
                    ForEach(LibraryCatalog.bannerCategories) { category in
                        Button { openCategory = category.id } label: {
                            LibraryBannerRow(
                                category: category,
                                summary: category.id.summary(from: store.snapshot)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("library-card-\(category.id.rawValue)")
                    }
                }
                .padding(.horizontal, AimMetrics.space16)
                .padding(.bottom, AimMetrics.space28)
            }
            .background(Color.aimCanvas)
            .navigationTitle("资料库")
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.load() }
            // 每次进入这个 Tab 都重新拉取：记录可能是在时间线或 AIM 里新增的，
            // 只加载一次会让资料库停在过期快照上。
            .task(id: session.pregnancyID) { await store.load() }
            .onAppear { Task { await store.load() } }
            .navigationDestination(item: $openCategory) { category in
                LibraryCategoryDetail(category: category, store: store, agentStore: agentStore)
            }
            .navigationDestination(item: $openTopic) { topic in
                EncyclopediaTopicView(topic: topic, store: store, agentStore: agentStore)
            }
            .navigationDestination(item: $openEntryID) { id in
                EncyclopediaEntryView(entryID: id, store: store, agentStore: agentStore)
            }
            .navigationDestination(item: $openReportID) { id in
                if let destinations, let report = store.snapshot.records.first(where: { $0.id == id }) {
                    RecordDetailView(
                        record: report, store: destinations.recordStore,
                        planStore: destinations.planStore, agentStore: agentStore)
                }
            }
            .fullScreenCover(isPresented: $showingAgent) {
                AgentView(store: agentStore) { showingAgent = false }
            }
        }
    }

    private var header: some View {
        AimPageHeader(caption: subtitle, title: "资料库") {
            AimCircleButton(symbol: "wand.and.sparkles", tinted: true, label: "AIM", identifier: "library-agent-button") {
                agentStore.focus(context: AgentContext(title: "资料库", summary: subtitle))
                showingAgent = true
            }
        }
    }

    private func sectionTitle(_ text: String, identifier: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Color.aimTextPrimary)
            .padding(.top, AimMetrics.space8)
            .accessibilityIdentifier(identifier)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let week = store.currentWeek { parts.append("孕 \(week) 周") }
        if !store.encyclopedia.isEmpty { parts.append("百科 \(store.encyclopedia.entries.count) 条") }
        let mine = store.snapshot.records.count
        parts.append(mine == 0 ? "我的还没有内容" : "我的 \(mine) 条")
        return parts.joined(separator: " · ")
    }
}

/// 「本周关注」。只在真有值得看的事时出现——空横幅比没有横幅更糟。
///
/// 颜色跟着急迫程度走：立即就医用危险色并直接给出拨号按钮，
/// 今天联系医院用提醒色，其余保持强调色。
private struct LibraryFocusBanner: View {
    let focus: LibraryFocus

    private var tint: Color {
        switch focus.level {
        case .urgent: .aimDanger
        case .soon: .aimWarning
        case .info: .aimAccent
        }
    }

    /// 浅危险底 / 浅提醒底上再放同色胶囊会看不出来，这两档改用卡片底色。
    private var tagBackground: Color {
        focus.level == .info ? .aimAccentSoft : .aimSurface
    }

    private var background: Color {
        switch focus.level {
        case .urgent: .aimDangerSoft
        case .soon: .aimWarningSoft
        case .info: .aimSurface
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Text("本周关注")
                .font(.caption2)
                .foregroundStyle(tint)
            Text(focus.headline)
                .font(focus.level == .urgent ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(focus.level == .urgent ? Color.aimDanger : Color.aimTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !focus.tags.isEmpty {
                HStack(spacing: AimMetrics.space4) {
                    ForEach(focus.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, AimMetrics.space8)
                            .padding(.vertical, 2)
                            .background(tagBackground, in: Capsule())
                            .foregroundStyle(tint)
                    }
                }
            }
            if focus.level == .urgent {
                // 紧急时不该还要用户自己去翻通讯录。
                Link(destination: URL(string: "tel://120")!) {
                    Label("拨打 120", systemImage: "phone.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AimMetrics.space8)
                        .background(Color.aimDanger, in: RoundedRectangle(
                            cornerRadius: AimMetrics.radiusButton, style: .continuous))
                        .foregroundStyle(Color.aimTextOnDanger)
                }
                .accessibilityIdentifier("library-focus-call")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AimMetrics.space16)
        .background(background, in: RoundedRectangle(
            cornerRadius: AimMetrics.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AimMetrics.radiusCard, style: .continuous)
                .stroke(Color.aimSeparator, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(tint).frame(width: 3)
        }
        .accessibilityIdentifier("library-focus-banner")
    }
}

private struct LibraryCategoryCard: View {
    let category: LibraryCategory
    let summary: LibrarySummary
    var trend: MetricTrend?

    var body: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Image(systemName: category.icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.aimAccent)
            Text(category.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.aimTextPrimary)
            Text(summary.headline)
                .font(.caption)
                .foregroundStyle(Color.aimTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let trend, trend.points.count > 1 {
                MetricSparkline(trend: trend)
            }
            if !summary.tags.isEmpty {
                HStack(spacing: AimMetrics.space4) {
                    ForEach(summary.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, AimMetrics.space8)
                            .padding(.vertical, 2)
                            .background(Color.aimSurfaceSunken, in: Capsule())
                            .foregroundStyle(Color.aimTextSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .aimCard()
    }
}

private struct LibraryBannerRow: View {
    let category: LibraryCategory
    let summary: LibrarySummary

    var body: some View {
        HStack(spacing: AimMetrics.space12) {
            Image(systemName: category.icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.aimDanger)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.aimTextPrimary)
                Text(summary.headline)
                    .font(.caption)
                    .foregroundStyle(Color.aimTextSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.aimTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .aimCard()
    }
}


/// 卡片上的迷你趋势条。只在有两个以上读数时出现——一个点画不出趋势。
private struct MetricSparkline: View {
    let trend: MetricTrend

    var body: some View {
        let values = trend.points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let span = max(high - low, 0.001)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let ratio = (value - low) / span
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(index == values.count - 1 ? Color.aimAccent : Color.aimAccentSoft)
                    .frame(height: 4 + CGFloat(ratio) * 14)
            }
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}
