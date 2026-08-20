import Foundation
import Observation

@MainActor
@Observable
final class AgentStore {
    var state: AgentSheetState = .idle
    var messages: [AgentMessage] = []
    var draft = ""
    var sessionID: String?
    var streamIndex = 0
    var continuationToken: String?

    var context: AgentContext?
    var activityLog: [AgentActivity] = []

    private var client: EveClient?
    private var activeTask: Task<Void, Never>?
    private var lastUserText: String?

    init(context: AgentContext? = nil) {
        self.context = context
    }

    func requestMessage(for text: String) -> String {
        guard let context else { return text }
        return "\(context.prompt)\n\n用户问题：\(text)"
    }

    /// Bring the current page's context into view without sending anything —
    /// used when the entry point is "quickly ask about what I'm looking at",
    /// not a specific question. Doesn't clear existing conversation history:
    /// this store is shared across every entry point, so switching context
    /// mid-conversation is expected, not a reset.
    func focus(context: AgentContext?) {
        self.context = context
    }

    /// Bring in a new context and immediately ask a specific question —
    /// used when the entry point already knows what to ask (e.g. "analyze
    /// this record"). Appends to the same shared conversation.
    func ask(_ text: String, context: AgentContext?, environment: APIEnvironment) {
        self.context = context
        draft = text
        send(environment: environment)
    }

    func retryLast(environment: APIEnvironment) {
        guard let lastUserText else { return }
        draft = lastUserText
        messages.removeAll { $0.text == lastUserText && $0.isUser }
        send(environment: environment)
    }

    func send(environment: APIEnvironment) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        messages.append(AgentMessage(text: text, isUser: true))
        lastUserText = text
        let requestText = requestMessage(for: text)
        state = .streaming
        let client = EveClient(environment: environment)
        self.client = client
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            do {
                let events: AsyncThrowingStream<EveEvent, Error>
                if let sessionID = self?.sessionID {
                    events = try await client.send(sessionID: sessionID, message: requestText, from: self?.streamIndex ?? 0)
                } else {
                    events = try await client.start(message: requestText)
                    self?.sessionID = await client.currentSessionID
                }
                for try await event in events { self?.consume(event) }
            } catch {
                self?.fail(error.localizedDescription)
            }
        }
    }

    func approve(_ request: EveInputRequest, environment: APIEnvironment) {
        respond(request, approved: true, environment: environment)
    }

    func cancelApproval(_ request: EveInputRequest, environment: APIEnvironment) {
        respond(request, approved: false, environment: environment)
    }

    func stop() {
        activeTask?.cancel()
        state = .idle
    }

    func undo(_ activity: AgentActivity, environment: APIEnvironment) {
        guard let sessionID else { return }
        activityLog.removeAll { $0.id == activity.id }
        let client = EveClient(environment: environment)
        state = .streaming
        activeTask = Task { [weak self] in
            do {
                let events = try await client.send(
                    sessionID: sessionID,
                    message: "撤销上一次计划变更",
                    from: self?.streamIndex ?? 0
                )
                for try await event in events { self?.consume(event) }
            } catch {
                self?.fail(error.localizedDescription)
            }
        }
    }

    private func respond(_ request: EveInputRequest, approved: Bool, environment: APIEnvironment) {
        guard let sessionID else { return }
        let client = EveClient(environment: environment)
        state = .streaming
        activeTask = Task { [weak self] in
            do {
                try await client.respondToApproval(sessionID: sessionID, approvalID: request.requestID, approved: approved)
                let events = await client.resume(sessionID: sessionID, from: self?.streamIndex ?? 0)
                for try await event in events { self?.consume(event) }
            } catch {
                self?.fail(error.localizedDescription)
            }
        }
    }

    private func consume(_ event: EveEvent) {
        streamIndex = max(streamIndex, event.streamIndex)
        switch event.type {
        case .sessionStarted:
            break
        case .inputRequested:
            if let request = event.inputRequests.first { state = .awaitingApproval(request) }
        case .actionResult:
            state = .applied
            activityLog.insert(
                AgentActivity(id: UUID(), title: "已更新家庭计划", occurredAt: .now, canUndo: true),
                at: 0
            )
        case .messageCompleted:
            if let message = try? JSONDecoder().decode(EveMessageCompleted.self, from: event.data),
               AgentResponseText.shouldDisplay(finishReason: message.finishReason),
               let text = message.message {
                let cleaned = AgentResponseText.clean(text)
                if !cleaned.isEmpty { messages.append(AgentMessage(text: cleaned, isUser: false)) }
            }
        case .sessionWaiting:
            continuationToken = event.continuationToken
            if case .streaming = state { state = .idle }
        case .turnCompleted:
            if case .streaming = state { state = .idle }
        default:
            break
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
    }
}

private struct EveMessageCompleted: Decodable {
    let finishReason: String?
    let message: String?
}

struct AgentActivity: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let occurredAt: Date
    let canUndo: Bool
}
