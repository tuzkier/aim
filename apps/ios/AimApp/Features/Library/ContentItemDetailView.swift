import SwiftUI

/// Aim 自带条目的详情。
///
/// 这些条目此前只有标题和一行摘要、且不可点——用户看到的就是一堆读不下去的行。
/// 详情页把完整内容摊开，并明确标出「谁写的」以及能不能核对。
struct ContentItemDetailView: View {
    let item: ContentItem
    let collection: ContentCollection
    var agentStore: AgentStore?

    @State private var showingAgent = false

    var body: some View {
        List {
            Section {
                Text(item.summary)
                    .font(.body)
                    .foregroundStyle(Color.aimTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Color.aimSurface)

            if let url = item.verificationURL, let link = URL(string: url) {
                Section {
                    // 政策类内容不由 App 下结论，只提供官方核对入口。
                    Link(destination: link) {
                        Label("到官方渠道核对", systemImage: "arrow.up.right.square")
                    }
                }
                .listRowBackground(Color.aimSurface)
            }

            if let agentStore {
                Section {
                    Button {
                        agentStore.focus(context: AgentContext(
                            title: item.title,
                            summary: "关于「\(item.title)」：\(item.summary)"))
                        showingAgent = true
                    } label: {
                        Label("就这条问问 AIM", systemImage: "wand.and.sparkles")
                            .foregroundStyle(Color.aimAccent)
                    }
                    .accessibilityIdentifier("content-ask-agent")
                }
                .listRowBackground(Color.aimSurface)
            }

            Section {
                Text("来源：\(collection.source)。这是 Aim 自带的通用参考，具体尺度以产检医生的意见为准。")
                    .font(.caption)
                    .foregroundStyle(Color.aimTextTertiary)
            }
            .listRowBackground(Color.aimSurface)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.aimCanvas)
        .navigationTitle(item.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .fullScreenCover(isPresented: $showingAgent) {
            if let agentStore {
                AgentView(store: agentStore) { showingAgent = false }
            }
        }
    }
}
