import ExyteChat
import SwiftUI

struct AgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSessionStore.self) private var session
    @State private var store: AgentStore

    init(initialDraft: String = "", context: AgentContext? = nil) {
        let store = AgentStore(context: context)
        store.draft = initialDraft
        _store = State(initialValue: store)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let context = store.context {
                    AgentContextCard(context: context)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }

                if store.messages.isEmpty {
                    welcomeContent
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }

                ChatView(messages: AgentChatAdapter.messages(from: store.messages)) { draft in
                    store.draft = draft.text
                    store.send(environment: session.environment)
                }
                .setAvailableInputs([.text])
                .localization(chatLocalization)
                .showDateHeaders(false)
                .showMessageMenuOnLongPress(false)
                .keyboardDismissMode(UIScrollView.KeyboardDismissMode.interactive)
                .betweenListAndInputViewBuilder {
                    statusView
                }
                .chatTheme(chatTheme)
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
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("我在这里陪你一起理清", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Color.aimAccent)
            Text("可以问孕期变化、最近记录或接下来要做的事。涉及计划变更时，我会先让你确认。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .aimWarmCard()
    }

    private var chatLocalization: ChatLocalization {
        ChatLocalization(
            inputPlaceholder: "告诉我你现在在担心什么",
            signatureText: "补充说明",
            cancelButtonText: "取消",
            recentToggleText: "最近",
            waitingForNetwork: "等待网络",
            recordingText: "录音中",
            replyToText: "回复"
        )
    }

    private var chatTheme: ChatTheme {
        ChatTheme(colors: .init(
            mainBG: Color.aimWarmBackground,
            mainTint: Color.aimAccent,
            mainText: .primary,
            mainCaptionText: .secondary,
            messageMyBG: Color.aimAccent,
            messageMyText: .white,
            messageFriendBG: Color.aimWarmSurface,
            messageFriendText: .primary,
            inputBG: Color.aimWarmSurface,
            inputText: .primary,
            inputPlaceholderText: .secondary,
            sendButtonBackground: Color.aimAccent
        ))
    }

    @ViewBuilder
    private var statusView: some View {
        switch store.state {
        case .awaitingApproval(let request):
            ApprovalBar(request: request) {
                store.approve(request, environment: session.environment)
            } onCancel: {
                store.cancelApproval(request, environment: session.environment)
            }
        case .streaming:
            Label("正在整理回答…", systemImage: "ellipsis")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.aimSoftRose)
        default:
            EmptyView()
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
