import ExyteChat
import SwiftUI

/// The Agent's one persistent conversation. Every entry point in the app —
/// the Agent tab itself, "ask about this page" icons, "analyze this record"
/// buttons — shares this same store rather than spinning up a throwaway
/// session, so switching to it from anywhere continues the same relationship
/// instead of starting over.
///
/// How it's *presented* still varies with the entry point's purpose: as the
/// Agent tab's root, there's no `onClose` and no close button, because
/// navigating away is just switching tabs. Opened from a quick-ask entry
/// point (header icon, focus card, "analyze this record"), it's shown as a
/// dismissible overlay — that entry point's whole purpose is "let me stay
/// where I am and just ask" — so pass `onClose` to get a close button back.
struct AgentView: View {
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: AgentStore
    var onClose: (() -> Void)?

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
                    quickPromptRow
                        .padding(.bottom, 12)
                }

                if !store.activityLog.isEmpty {
                    activitySection
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
            .navigationTitle("AIM")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", action: onClose)
                    }
                }
            }
            .background(Color.aimCanvas)
            .sheet(item: pendingApproval) { request in
                AgentDiffSheet(preview: AgentChangePreview.from(request)) {
                    store.approve(request, environment: session.environment)
                } onDismiss: {
                    store.cancelApproval(request, environment: session.environment)
                }
            }
        }
    }

    private var pendingApproval: Binding<EveInputRequest?> {
        Binding(
            get: {
                if case let .awaitingApproval(request) = store.state { return request }
                return nil
            },
            set: { newValue in
                if newValue == nil, case let .awaitingApproval(request) = store.state {
                    store.cancelApproval(request, environment: session.environment)
                }
            }
        )
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("我在这里陪你一起理清", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Color.aimAccent)
            Text("可以问孕期变化、最近记录或接下来要做的事。涉及计划变更时，我会先让你确认。")
                .font(.subheadline)
                .foregroundStyle(Color.aimTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .aimCard()
    }

    private let quickPrompts = ["这周还有什么要准备？", "帮我看看最近的记录", "我现在有点不舒服"]

    private var quickPromptRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AimMetrics.space8) {
                ForEach(quickPrompts, id: \.self) { prompt in
                    Button(prompt) {
                        store.draft = prompt
                        store.send(environment: session.environment)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.aimAccent)
                    .padding(.horizontal, AimMetrics.space12)
                    .padding(.vertical, AimMetrics.space8)
                    .background(Color.aimSurface, in: Capsule())
                    .overlay { Capsule().stroke(Color.aimAccent.opacity(0.2), lineWidth: 1) }
                    .accessibilityIdentifier("agent-quick-prompt")
                }
            }
            .padding(.horizontal, AimMetrics.space16)
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Text("最近处理").aimLabelStyle()
            ForEach(store.activityLog.prefix(3)) { activity in
                HStack(spacing: AimMetrics.space8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.aimSuccess)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.title)
                            .font(.subheadline)
                            .foregroundStyle(Color.aimTextPrimary)
                        Text(activity.occurredAt, style: .time)
                            .font(.footnote)
                            .foregroundStyle(Color.aimTextSecondary)
                    }
                    Spacer()
                    if activity.canUndo {
                        Button("撤销") { store.undo(activity, environment: session.environment) }
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.aimAccent)
                    }
                }
            }
        }
        .padding(.horizontal, AimMetrics.space16)
        .padding(.vertical, AimMetrics.space8)
        .accessibilityIdentifier("agent-activity-log")
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
            mainBG: Color.aimCanvas,
            mainTint: Color.aimAccent,
            mainText: Color.aimTextPrimary,
            mainCaptionText: Color.aimTextSecondary,
            messageMyBG: Color.aimAccent,
            messageMyText: Color.aimTextOnAccent,
            messageFriendBG: Color.aimSurface,
            messageFriendText: Color.aimTextPrimary,
            inputBG: Color.aimSurface,
            inputText: Color.aimTextPrimary,
            inputPlaceholderText: Color.aimTextSecondary,
            sendButtonBackground: Color.aimAccent
        ))
    }

    @ViewBuilder
    private var statusView: some View {
        switch store.state {
        case .awaitingApproval:
            EmptyView()
        case .streaming:
            HStack(spacing: AimMetrics.space8) {
                ProgressView().controlSize(.small)
                Text("正在整理回答…")
                    .font(.footnote)
                    .foregroundStyle(Color.aimTextSecondary)
                Spacer()
                Button("停止") { store.stop() }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.aimAccent)
                    .accessibilityIdentifier("agent-stop")
            }
            .padding(.horizontal, AimMetrics.space16)
            .padding(.vertical, AimMetrics.space8)
        case .failed(let message):
            HStack(alignment: .firstTextBaseline, spacing: AimMetrics.space8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.aimTextSecondary)
                Spacer()
                Button("重试") { store.retryLast(environment: session.environment) }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.aimAccent)
                    .accessibilityIdentifier("agent-retry")
            }
            .padding(.horizontal, AimMetrics.space16)
            .padding(.vertical, AimMetrics.space12)
            .background(Color.aimDangerSoft)
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
                .background(Color.aimAccentSoft, in: Circle())
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
        .background(Color.aimAccentSoft.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("agent-current-context")
    }
}
