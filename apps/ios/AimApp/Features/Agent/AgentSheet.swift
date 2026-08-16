import SwiftUI

struct AgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSessionStore.self) private var session
    @State private var store = AgentStore()

    init(initialDraft: String = "") {
        let store = AgentStore()
        store.draft = initialDraft
        _store = State(initialValue: store)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if store.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("我会先理解你的孕期上下文", systemImage: "sparkles")
                                    .font(.headline)
                                Text("你可以说：‘帮我看看这周还有什么要准备’，我会先给出方案；涉及计划变更时，会明确等你确认。")
                                    .foregroundStyle(.secondary)
                            }
                            .aimWarmCard()
                        }
                        ForEach(store.messages) { message in
                            HStack {
                                if message.isUser { Spacer() }
                                Text(message.text)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(message.isUser ? Color.aimAccent : Color.aimWarmSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .foregroundStyle(message.isUser ? .white : .primary)
                                if !message.isUser { Spacer() }
                            }
                        }
                    }
                    .padding()
                }

                if case .awaitingApproval(let request) = store.state {
                    ApprovalBar(request: request) {
                        store.approve(request, environment: session.environment)
                    } onCancel: {
                        store.cancelApproval(request, environment: session.environment)
                    }
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("告诉我你现在在担心什么", text: $store.draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    Button {
                        store.send(environment: session.environment)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("问一问")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .background(Color.aimWarmBackground)
        }
    }
}

private struct ApprovalBar: View {
    let request: EveInputRequest
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.prompt ?? "要执行这项计划变更吗？")
                .font(.subheadline.weight(.semibold))
            HStack {
                Button("暂不执行", action: onCancel).buttonStyle(.bordered)
                Button("确认执行", action: onApprove).buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.aimSoftRose)
    }
}
