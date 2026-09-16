import XCTest
@testable import AimApp

/// 服务端把账号清掉之后，手机上那张 token 就作废了。此前 App 没有任何一处
/// 处理 401：它抱着废票一遍遍重试，界面停在空的孕期页，永远回不到登录页。
///
/// 真机上实际发生过——生产库清空后打开 App，`content/*` 这类免鉴权接口 200，
/// 其余全部 401，而 App 毫无反应。真实用户 token 过期时会撞上同一件事。
final class APIErrorUnauthorizedTests: XCTestCase {
    func testOnly401CountsAsAnExpiredSession() {
        XCTAssertTrue(APIError.http(status: 401, body: "").isUnauthorized)
        // 403 是「这个账号不能做这件事」，票本身是好的，不该把人踢下线。
        XCTAssertFalse(APIError.http(status: 403, body: "").isUnauthorized)
        XCTAssertFalse(APIError.http(status: 404, body: "").isUnauthorized)
        XCTAssertFalse(APIError.http(status: 500, body: "").isUnauthorized)
        XCTAssertFalse(APIError.invalidResponse.isUnauthorized)
        XCTAssertFalse(APIError.notConfigured.isUnauthorized)
    }
}

private final class StatusStubProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class SessionExpiryNotificationTests: XCTestCase {
    private func session(status: Int) -> URLSession {
        StatusStubProtocol.status = status
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StatusStubProtocol.self]
        return URLSession(configuration: config)
    }

    private var probe: URLRequest {
        URLRequest(url: URL(string: "http://stub.local/api/v1/pregnancies")!)
    }

    func test401BroadcastsThatTheSessionExpired() async {
        let expectation = expectation(forNotification: .aimSessionExpired, object: nil)

        _ = try? await session(status: 401).aimData(for: probe)

        await fulfillment(of: [expectation], timeout: 2)
    }

    /// 注销要密码的端点用 401 表示「密码不对」；关掉广播后错误仍然抛出，但不会清会话。
    func test401WithoutBroadcastStillThrowsButDoesNotExpireTheSession() async {
        let expectation = expectation(forNotification: .aimSessionExpired, object: nil)
        expectation.isInverted = true

        var thrown: Error?
        do {
            _ = try await session(status: 401).aimData(for: probe, broadcastsUnauthorized: false)
        } catch {
            thrown = error
        }

        guard case let .http(status, _)? = thrown as? APIError else {
            return XCTFail("应当抛出 APIError.http，实际：\(String(describing: thrown))")
        }
        XCTAssertEqual(status, 401)
        await fulfillment(of: [expectation], timeout: 1)
    }

    /// 别的失败不能把人踢下线——网络抖一下就退出登录是更糟的体验。
    func testOtherFailuresDoNotBroadcast() async {
        let expectation = expectation(forNotification: .aimSessionExpired, object: nil)
        expectation.isInverted = true

        _ = try? await session(status: 500).aimData(for: probe)

        await fulfillment(of: [expectation], timeout: 1)
    }
}

@MainActor
final class AppSessionStoreExpiryTests: XCTestCase {
    private let suiteName = "aim.tests.session-expiry"

    private func makeStore() -> (AppSessionStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = AppSessionStore(defaults: defaults, keychain: KeychainStore(service: suiteName))
        store.configure(
            accountID: UUID(), familyID: UUID(), pregnancyID: UUID(), bearerToken: "aim.v1.stale"
        )
        return (store, defaults)
    }

    func testExpiryClearsTheStoredSession() {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertTrue(store.isConfigured)

        store.handleSessionExpired()

        XCTAssertFalse(store.isConfigured, "票作废后应当退回登录页，而不是抱着废票重试")
        XCTAssertNil(store.bearerToken)
        XCTAssertNil(store.familyID, "旧的家庭/孕期 ID 在服务端已经不存在，一并清掉")
    }

    /// 光有 handleSessionExpired() 不够——必须真的接在通知上，否则网络层喊了没人听。
    func testStoreIsWiredToTheExpiryNotification() async {
        let (store, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        NotificationCenter.default.post(name: .aimSessionExpired, object: nil)

        let deadline = Date().addingTimeInterval(2)
        while store.isConfigured, Date() < deadline {
            // 观察者派发在 main queue 上，得让它跑起来。
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertFalse(store.isConfigured, "AppSessionStore 应当订阅 aimSessionExpired")
    }
}
