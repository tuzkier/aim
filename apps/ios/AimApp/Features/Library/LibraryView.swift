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

    private let columns = [
        GridItem(.flexible(), spacing: AimMetrics.space12),
        GridItem(.flexible(), spacing: AimMetrics.space12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AimMetrics.space12) {
                    header
                    if let focus = LibraryFocus.make(from: store.snapshot) {
                        LibraryFocusBanner(focus: focus)
                    }
                    LazyVGrid(columns: columns, spacing: AimMetrics.space12) {
                        ForEach(LibraryCatalog.gridCategories) { category in
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
                .padding(AimMetrics.space16)
            }
            .background(Color.aimCanvas)
            .navigationTitle("资料库")
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.load() }
            .task(id: session.pregnancyID) {
                guard store.snapshot.records.isEmpty, store.safetyRules.isEmpty else { return }
                await store.load()
            }
            .navigationDestination(item: $openCategory) { category in
                LibraryCategoryDetail(category: category, store: store, agentStore: agentStore)
            }
            .fullScreenCover(isPresented: $showingAgent) {
                AgentView(store: agentStore) { showingAgent = false }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: AimMetrics.space4) {
                Text("资料库")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color.aimTextPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.aimTextTertiary)
            }
            Spacer()
            Button {
                agentStore.focus(context: AgentContext(title: "资料库", summary: subtitle))
                showingAgent = true
            } label: {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(Color.aimAccentSoft, in: Circle())
                    .foregroundStyle(Color.aimAccent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library-agent-button")
            .accessibilityLabel("AIM")
        }
    }

    private var subtitle: String {
        let count = store.snapshot.records.count
        return count == 0 ? "还没有收录内容" : "已收录 \(count) 条"
    }
}

/// 「本周关注」。只在真有值得看的事时出现——空横幅比没有横幅更糟。
private struct LibraryFocusBanner: View {
    let focus: LibraryFocus

    var body: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Text("本周关注")
                .font(.caption2)
                .foregroundStyle(Color.aimAccent)
            Text(focus.headline)
                .font(.subheadline)
                .foregroundStyle(Color.aimTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !focus.tags.isEmpty {
                HStack(spacing: AimMetrics.space4) {
                    ForEach(focus.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, AimMetrics.space8)
                            .padding(.vertical, 2)
                            .background(Color.aimAccentSoft, in: Capsule())
                            .foregroundStyle(Color.aimAccent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aimCard()
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.aimAccent).frame(width: 3)
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
