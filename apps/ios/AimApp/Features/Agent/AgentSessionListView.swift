import SwiftUI

/// 历史对话列表。
///
/// 只列标题和最后活跃时间——内容在 Eve，点进去才重放。列表里放摘要会逼我们
/// 在自己库里复制一份消息，那既冗余又多一处隐私泄漏面。
struct AgentSessionListView: View {
    @Environment(AppSessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: AgentSessionStore
    let onOpen: (AgentSessionSummary) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty, store.isLoading {
                    ProgressView("正在加载")
                } else if store.sessions.isEmpty {
                    AimEmptyState(
                        title: "还没有历史对话",
                        message: "问过 AIM 的每一段对话都会出现在这里，随时能翻回去。"
                    )
                } else {
                    list
                }
            }
            .navigationTitle("历史对话")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .background(Color.aimCanvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await store.load(environment: session.environment) }
            .accessibilityIdentifier("agent-session-list")
        }
    }

    private var list: some View {
        List {
            ForEach(store.sessions) { item in
                Button {
                    onOpen(item)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.aimTextPrimary)
                            .lineLimit(1)
                        Text(item.lastActiveAt, format: .relative(presentation: .named))
                            .font(.footnote)
                            .foregroundStyle(Color.aimTextSecondary)
                    }
                }
                .accessibilityIdentifier("agent-session-row")
                .listRowBackground(Color.aimSurface)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await store.delete(item, environment: session.environment) }
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.load(environment: session.environment) }
    }
}
