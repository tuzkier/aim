import XCTest
@testable import AimApp

/// 服务端把一轮讲完后不会再吐字节，但连接还开着。此前客户端一直挂在
/// `for try await event in events` 上等下一条，60 秒后 URLSession 抛
/// `NSURLErrorTimedOut`，被 catch 接住变成一句「The request timed out.」。
///
/// 后果不是多一条错误提示那么轻：回答早已正常显示、反问也已进入等待回答态，
/// 一分钟后被这条假错误整个覆盖掉。
///
/// 这个桩刻意「发完就装死」——发完事件后不调 urlProtocolDidFinishLoading，
/// 完全复刻线上那条挂着的连接。修复前这个测试会一直等到超时。
private final class HangingStreamProtocol: URLProtocol {
    /// 发完事件后不结束响应，模拟服务端把连接留着。
    static var body = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/x-ndjson"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        // 故意不调 client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class EveStreamTests: XCTestCase {
    private func makeClient() async -> EveClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HangingStreamProtocol.self]
        // 真实默认是 60s。这里压到 5s：修复失效时测试很快红，而不是卡一分钟。
        config.timeoutIntervalForRequest = 5
        return EveClient(environment: .test, session: URLSession(configuration: config))
    }

    /// session.waiting 是「轮到你了」的标记，收到它就该收口。
    func testStreamFinishesOnSessionWaitingInsteadOfHangingUntilTimeout() async throws {
        HangingStreamProtocol.body = """
        {"type":"session.started","data":{}}
        {"type":"message.completed","data":{"message":"好的","finishReason":"stop"}}
        {"type":"turn.completed","data":{}}
        {"type":"session.waiting","data":{"continuationToken":"ct-1"}}

        """

        var received: [String] = []
        let client = await makeClient()
        for try await event in await client.resume(sessionID: "s-1", from: 0) {
            received.append(event.rawType)
        }

        XCTAssertEqual(
            received,
            ["session.started", "message.completed", "turn.completed", "session.waiting"],
            "应当收完这一轮就正常结束，而不是抛超时"
        )
    }

    func testTerminalEventsAreOnlyTheOnesThatEndTheTurn() {
        func event(_ type: String) -> EveEvent {
            EveEvent(type: EveEventType(rawValue: type), rawType: type, eventID: nil, streamIndex: 0, data: Data("{}".utf8))
        }
        XCTAssertTrue(event("session.waiting").isTerminal)
        XCTAssertTrue(event("session.completed").isTerminal)
        // turn.completed 之后服务端还会补 session.waiting，提前收口会漏掉它带的
        // continuationToken，所以它不算终止。
        XCTAssertFalse(event("turn.completed").isTerminal)
        XCTAssertFalse(event("input.requested").isTerminal)
        XCTAssertFalse(event("message.appended").isTerminal)
    }
}
