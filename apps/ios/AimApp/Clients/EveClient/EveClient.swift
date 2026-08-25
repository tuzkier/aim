import Foundation

actor EveClient {
    private let environment: APIEnvironment
    private let session: URLSession
    private(set) var currentSessionID: String?

    init(environment: APIEnvironment, session: URLSession = .shared) {
        self.environment = environment
        self.session = session
    }

    func start(message: String) async throws -> AsyncThrowingStream<EveEvent, Error> {
        let body = try JSONEncoder().encode(["message": message])
        let request = environment.eveRequest(path: "/eve/v1/session", method: "POST", body: body)
        let (data, response) = try await session.aimData(for: request)
        let sessionID = try JSONDecoder().decode(EveSessionCreated.self, from: data).sessionID ?? response.value(forHTTPHeaderField: "x-eve-session-id")
        guard let sessionID, !sessionID.isEmpty else { throw APIError.invalidResponse }
        currentSessionID = sessionID
        return stream(sessionID: sessionID, from: 0)
    }

    func resume(sessionID: String, from index: Int) -> AsyncThrowingStream<EveEvent, Error> {
        currentSessionID = sessionID
        return stream(sessionID: sessionID, from: index)
    }

    func send(sessionID: String, message: String, from index: Int) async throws -> AsyncThrowingStream<EveEvent, Error> {
        let body = try JSONEncoder().encode(["message": message])
        let request = environment.eveRequest(path: "/eve/v1/session/\(sessionID)", method: "POST", body: body)
        _ = try await session.aimData(for: request)
        currentSessionID = sessionID
        return stream(sessionID: sessionID, from: index)
    }

    func respondToApproval(sessionID: String, approvalID: String, approved: Bool) async throws {
        try await postInputResponse(
            sessionID: sessionID,
            response: EveInputResponse(
                requestID: approvalID, optionID: approved ? "approve" : "cancel", text: nil
            )
        )
    }

    /// 回答 Agent 的反问。和批准不同，这里要把用户真正选的选项或打的字送回去——
    /// 批准那条路把 optionID 写死成 "approve"/"cancel"，用来答题等于什么都没说。
    func respondToInput(
        sessionID: String,
        requestID: String,
        optionID: String?,
        text: String?
    ) async throws {
        try await postInputResponse(
            sessionID: sessionID,
            response: EveInputResponse(requestID: requestID, optionID: optionID, text: text)
        )
    }

    private func postInputResponse(sessionID: String, response: EveInputResponse) async throws {
        let body = try JSONEncoder().encode(["inputResponses": [response]])
        let request = environment.eveRequest(path: "/eve/v1/session/\(sessionID)", method: "POST", body: body)
        _ = try await session.aimData(for: request)
    }

    func cancel(sessionID: String) async throws {
        let request = environment.eveRequest(path: "/eve/v1/session/\(sessionID)/cancel", method: "POST")
        _ = try await session.aimData(for: request)
    }

    private func stream(sessionID: String, from index: Int) -> AsyncThrowingStream<EveEvent, Error> {
        let environment = environment
        let session = session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var path = "/eve/v1/session/\(sessionID)/stream"
                    if index > 0 { path += "?startIndex=\(index)" }
                    var request = environment.eveRequest(path: path)
                    request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                        throw APIError.invalidResponse
                    }
                    var decoder = EveNDJSONDecoder(startIndex: index)
                    for try await line in bytes.lines {
                        var lineData = Data(line.utf8)
                        lineData.append(0x0A)
                        for event in try decoder.append(lineData) {
                            continuation.yield(event)
                            // 服务端说完了就收口。继续读下去只会空等到超时，
                            // 而那条超时会被当成真错误覆盖掉已经收到的回答。
                            if event.isTerminal {
                                continuation.finish()
                                return
                            }
                        }
                    }
                    for event in try decoder.finish() { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    if !Task.isCancelled { continuation.finish(throwing: error) }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private struct EveSessionCreated: Decodable {
    let sessionID: String?

    enum CodingKeys: String, CodingKey { case sessionID = "sessionId" }
}
