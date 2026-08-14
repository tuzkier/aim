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

    private var client: EveClient?
    private var activeTask: Task<Void, Never>?

    func send(environment: APIEnvironment) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        messages.append(AgentMessage(text: text, isUser: true))
        state = .streaming
        let client = EveClient(environment: environment)
        self.client = client
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            do {
                let events: AsyncThrowingStream<EveEvent, Error>
                if let sessionID = self?.sessionID {
                    events = try await client.send(sessionID: sessionID, message: text, from: self?.streamIndex ?? 0)
                } else {
                    events = try await client.start(message: text)
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
        case .messageCompleted:
            if let message = try? JSONDecoder().decode(EveMessageCompleted.self, from: event.data), let text = message.message, !text.isEmpty {
                messages.append(AgentMessage(text: text, isUser: false))
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
    let message: String?
}
