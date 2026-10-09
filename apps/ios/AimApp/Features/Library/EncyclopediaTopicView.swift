import SwiftUI

/// 一个百科主题下的全部条目。本周相关的排前面并标出来。
struct EncyclopediaTopicView: View {
    let topic: EncyclopediaTopic
    let store: LibraryStore
    let agentStore: AgentStore

    var body: some View {
        List {
            ForEach(store.encyclopedia.entries(inTopic: topic.id, week: store.currentWeek)) { entry in
                NavigationLink {
                    EncyclopediaEntryView(entryID: entry.id, store: store, agentStore: agentStore)
                } label: {
                    EncyclopediaEntryRow(entry: entry, week: store.currentWeek)
                }
                .accessibilityIdentifier("encyclopedia-entry-\(entry.id)")
                .listRowBackground(Color.aimSurface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.aimCanvas)
        .navigationTitle(topic.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

/// 百科条目在列表里的一行。主题页与「吃什么 · 饮食提示」共用。
struct EncyclopediaEntryRow: View {
    let entry: EncyclopediaEntrySummary
    let week: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AimMetrics.space8) {
                if entry.isTimely(week: week) {
                    Text("本周")
                        .font(.caption2)
                        .padding(.horizontal, AimMetrics.space8)
                        .padding(.vertical, 1)
                        .background(Color.aimAccentSoft, in: Capsule())
                        .foregroundStyle(Color.aimAccent)
                }
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.aimTextPrimary)
            }
            Text(entry.summary)
                .font(.footnote)
                .foregroundStyle(Color.aimTextSecondary)
                .lineLimit(2)
        }
    }
}
