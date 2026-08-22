import XCTest
@testable import AimApp

final class APIEndpointConfigurationTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "aim.tests.endpoints"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsToDeployedEnvironment() {
        XCTAssertEqual(
            APIEndpointConfiguration.apiBaseURL(defaults: defaults, arguments: []),
            APIEndpointConfiguration.remote
        )
        XCTAssertEqual(
            APIEndpointConfiguration.eveBaseURL(defaults: defaults, arguments: []),
            APIEndpointConfiguration.remote
        )
    }

    func testLocalArgumentSelectsComposeStack() {
        let args = [APIEndpointConfiguration.localArgument]
        XCTAssertEqual(
            APIEndpointConfiguration.apiBaseURL(defaults: defaults, arguments: args),
            APIEndpointConfiguration.localAPI
        )
        XCTAssertEqual(
            APIEndpointConfiguration.eveBaseURL(defaults: defaults, arguments: args),
            APIEndpointConfiguration.localEve
        )
    }

    func testUserDefaultsOverrideWinsOverLocalArgument() {
        defaults.set("http://REDACTED_LAN_HOST:8100", forKey: APIEndpointConfiguration.Keys.apiBaseURL)

        XCTAssertEqual(
            APIEndpointConfiguration.apiBaseURL(
                defaults: defaults,
                arguments: [APIEndpointConfiguration.localArgument]
            ),
            URL(string: "http://REDACTED_LAN_HOST:8100")!
        )
        // 只覆盖了 api，eve 仍走 -local 规则
        XCTAssertEqual(
            APIEndpointConfiguration.eveBaseURL(
                defaults: defaults,
                arguments: [APIEndpointConfiguration.localArgument]
            ),
            APIEndpointConfiguration.localEve
        )
    }

    func testMalformedOverrideFallsBackToDefault() {
        defaults.set("没有 scheme 的字符串", forKey: APIEndpointConfiguration.Keys.apiBaseURL)

        XCTAssertEqual(
            APIEndpointConfiguration.apiBaseURL(defaults: defaults, arguments: []),
            APIEndpointConfiguration.remote
        )
    }

    /// 验证环境的 Nginx 按路径前缀分流，两个服务共用 80 端口，
    /// 因此 baseURL 相同也必须拼出各自正确的绝对地址。
    func testRemoteBaseURLsComposeDistinctPaths() {
        let environment = APIEnvironment(
            baseURL: APIEndpointConfiguration.apiBaseURL(defaults: defaults, arguments: []),
            eveBaseURL: APIEndpointConfiguration.eveBaseURL(defaults: defaults, arguments: []),
            bearerToken: nil,
            accountID: nil,
            familyID: nil,
            pregnancyID: nil
        )

        XCTAssertEqual(
            environment.businessRequest(path: "/api/v1/health").url?.absoluteString,
            "http://REDACTED_HOST/api/v1/health"
        )
        XCTAssertEqual(
            environment.eveRequest(path: "/eve/v1/session", method: "POST").url?.absoluteString,
            "http://REDACTED_HOST/eve/v1/session"
        )
    }
}
