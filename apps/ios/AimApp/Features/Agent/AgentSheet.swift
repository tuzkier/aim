import SwiftUI

struct AgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSessionStore.self) private var session
    @State private var store: AgentStore
    @FocusState private var inputFocused

    private let quickPrompts = [
        "这周还有什么要准备？",
        "帮我看看最近的记录",
        "我现在有点不舒服"
    ]

    init(initialDraft: String = "", context: AgentContext? = nil) {
        let store = AgentStore(context: context)
        store.draft = initialDraft
        _store = State(initialValue: store)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if let context = store.context {
                                AgentContextCard(context: context)
                                    .id("context")
                            }

                            if store.messages.isEmpty {
                                welcomeContent
                            } else {
                                ForEach(store.messages) { message in
                                    AgentMessageBubble(message: message)
                                        .id(message.id)
                                }
                            }

                            if case .streaming = store.state {
                                TypingIndicator()
                                    .id("typing")
                            }

                            if case let .failed(message) = store.state {
                                AgentErrorCard(message: message)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: store.messages.count) { _, _ in scrollToBottom(proxy) }
                    .onChange(of: store.state) { _, _ in scrollToBottom(proxy) }
                }

                if case .awaitingApproval(let request) = store.state {
                    ApprovalBar(request: request) {
                        store.approve(request, environment: session.environment)
                    } onCancel: {
                        store.cancelApproval(request, environment: session.environment)
                    }
                }

                inputBar
            }
            .navigationTitle("问一问")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .background(Color.aimWarmBackground)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.aimAccent)
                    Text("我在这里陪你一起理清")
                        .font(.headline)
                }
                Text("可以问孕期变化、最近记录或接下来要做的事。涉及计划变更时，我会先让你确认。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .aimWarmCard()

            VStack(alignment: .leading, spacing: 9) {
                Text("你可以这样问")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPrompts, id: \.self) { prompt in
                            Button(prompt) {
                                store.draft = prompt
                                inputFocused = true
                            }
                            .font(.subheadline)
                            .foregroundStyle(Color.aimAccent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.aimWarmSurface, in: Capsule())
                            .overlay { Capsule().stroke(Color.aimAccent.opacity(0.2), lineWidth: 1) }
                            .accessibilityIdentifier("agent-quick-prompt")
                        }
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("告诉我你现在在担心什么", text: $store.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(submit)
                .accessibilityIdentifier("agent-input")

            if case .streaming = store.state {
                Button { store.stop() } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("停止回答")
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.aimAccent)
                }
                .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("发送")
                .accessibilityIdentifier("agent-send")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func submit() {
        guard !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        inputFocused = false
        store.send(environment: session.environment)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

private struct AgentContextCard: View {
    let context: AgentContext

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "scope")
                .foregroundStyle(Color.aimAccent)
                .frame(width: 26, height: 26)
                .background(Color.aimSoftSand, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("正在查看 · \(context.title)")
                    .font(.subheadline.weight(.semibold))
                Text(context.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.aimSoftSand.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("agent-current-context")
    }
}

private struct AgentMessageBubble: View {
    let message: AgentMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser { Spacer(minLength: 44) }
            if !message.isUser {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.aimAccent)
                    .frame(width: 24, height: 24)
                    .background(Color.aimSoftSand, in: Circle())
            }
            Text(message.text)
                .font(.body)
                .foregroundStyle(message.isUser ? .white : .primary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(message.isUser ? Color.aimAccent : Color.aimWarmSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    if !message.isUser {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                    }
                }
            if !message.isUser { Spacer(minLength: 36) }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }
}

private struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("正在理解你的问题…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.aimWarmSurface, in: Capsule())
        .accessibilityLabel("Agent 正在回答")
    }
}

private struct AgentErrorCard: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .font(.footnote)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.aimSoftRose, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ApprovalBar: View {
    let request: EveInputRequest
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("需要你的确认", systemImage: "checkmark.shield")
                .font(.subheadline.weight(.semibold))
            Text(request.prompt ?? "要执行这项计划变更吗？")
                .font(.subheadline)
            HStack(spacing: 10) {
                Button("暂不执行", action: onCancel)
                    .buttonStyle(.bordered)
                Button("确认执行", action: onApprove)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.aimSoftRose, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
