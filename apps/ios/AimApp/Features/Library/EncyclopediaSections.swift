import SwiftUI

/// 资料库首页的「这周读什么」：横向滑动的卡片，取覆盖本周的百科条目。
/// 这是资料库随孕期变化的主要位置——不同孕周打开看到的不一样。
struct EncyclopediaWeeklyPicks: View {
    let week: Int
    let picks: [EncyclopediaEntrySummary]
    let topics: [EncyclopediaTopic]
    let open: (EncyclopediaEntrySummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Text("孕 \(week) 周，这周读什么")
                .font(.headline)
                .foregroundStyle(Color.aimTextPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: AimMetrics.space12) {
                    ForEach(picks) { entry in
                        Button { open(entry) } label: { card(entry) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("library-pick-\(entry.id)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-weekly-picks")
    }

    private func card(_ entry: EncyclopediaEntrySummary) -> some View {
        let topic = topics.first { $0.id == entry.topic }
        return VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Label(topic?.name ?? "", systemImage: topic?.icon ?? "book")
                .font(.caption2)
                .foregroundStyle(Color.aimAccent)
            Text(entry.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.aimTextPrimary)
                .lineLimit(1)
            Text(entry.summary)
                .font(.caption)
                .foregroundStyle(Color.aimTextSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(width: 200, height: 120, alignment: .topLeading)
        .aimCard()
    }
}

/// 资料库首页的「孕期百科」：六个主题卡。
struct EncyclopediaTopicGrid: View {
    let catalog: EncyclopediaCatalog
    let week: Int?
    let open: (EncyclopediaTopic) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: AimMetrics.space12),
        GridItem(.flexible(), spacing: AimMetrics.space12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: AimMetrics.space12) {
            ForEach(catalog.topics) { topic in
                Button { open(topic) } label: { card(topic) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-topic-\(topic.id)")
            }
        }
    }

    private func card(_ topic: EncyclopediaTopic) -> some View {
        let timely = catalog.timelyCount(topic: topic.id, week: week)
        return VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Image(systemName: topic.icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.aimAccent)
            Text(topic.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.aimTextPrimary)
            Text(timely > 0 ? "\(topic.count) 条 · 本周相关 \(timely)" : "\(topic.count) 条")
                .font(.caption)
                .foregroundStyle(Color.aimTextSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .aimCard()
    }
}
