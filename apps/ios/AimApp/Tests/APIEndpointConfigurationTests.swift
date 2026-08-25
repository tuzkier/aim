import XCTest
@testable import AimApp

/// 默认去向此前是「远端」，`-local` 才连本地。结果是模拟器和 UI 测试全都打在
/// 部署环境上——两天跑下来在生产库里堆了 253 个测试账号。
///
/// 现在反过来：**真机装的包才连部署环境**，模拟器和测试一律连本地 Compose。
/// 判据是编译期的 `targetEnvironment(simulator)`，不是启动参数——参数会忘记加，
/// 而忘记的代价是脏数据默默写进生产库。
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

    private func api(_ args: [String] = [], device: Bool) -> URL {
        APIEndpointConfiguration.apiBaseURL(defaults: defaults, arguments: args, isDeviceBuild: device)
    }

    private func eve(_ args: [String] = [], device: Bool) -> URL {
        APIEndpointConfiguration.eveBaseURL(defaults: defaults, arguments: args, isDeviceBuild: device)
    }

    /// 这条是这次改动的核心：测试跑在模拟器上，就不该碰到部署环境。
    func testSimulatorBuildDefaultsToLocalStack() {
        XCTAssertEqual(api(device: false), APIEndpointConfiguration.localAPI)
        XCTAssertEqual(eve(device: false), APIEndpointConfiguration.localEve)
    }

    func testDeviceBuildDefaultsToDeployedEnvironment() {
        XCTAssertEqual(api(device: true), APIEndpointConfiguration.remote)
        XCTAssertEqual(eve(device: true), APIEndpointConfiguration.remote)
    }

    /// 真正跑起来时用的那个无参版本，在模拟器上必须解析成本地。
    /// 这条守的是「测试自己」——它此刻就跑在模拟器里。
    func testProductionCallPathResolvesLocallyWhileTestsRun() {
        XCTAssertEqual(
            APIEndpointConfiguration.apiBaseURL(defaults: defaults, arguments: []),
            APIEndpointConfiguration.localAPI,
            "测试进程连的必须是本地栈，不能是 REDACTED_HOST"
        )
        XCTAssertFalse(APIEndpointConfiguration.isDeviceBuild, "测试跑在模拟器上")
    }

    /// 偶尔要拿模拟器验部署环境，留一个显式开关。
    func testRemoteArgumentPointsASimulatorAtTheDeployedEnvironment() {
        let args = [APIEndpointConfiguration.remoteArgument]
        XCTAssertEqual(api(args, device: false), APIEndpointConfiguration.remote)
        XCTAssertEqual(eve(args, device: false), APIEndpointConfiguration.remote)
    }

    /// 反向也要能走通：真机连开发机上的本地栈。
    func testLocalArgumentPointsADeviceAtTheComposeStack() {
        let args = [APIEndpointConfiguration.localArgument]
        XCTAssertEqual(api(args, device: true), APIEndpointConfiguration.localAPI)
        XCTAssertEqual(eve(args, device: true), APIEndpointConfiguration.localEve)
    }

    /// 两个参数同时给时，明确以 -local 为准，而不是看谁在数组里靠前。
    func testLocalWinsWhenBothArgumentsArePresent() {
        let args = [APIEndpointConfiguration.remoteArgument, APIEndpointConfiguration.localArgument]
        XCTAssertEqual(api(args, device: true), APIEndpointConfiguration.localAPI)
    }

    func testUserDefaultsOverrideWinsOverEverything() {
        defaults.set("http://REDACTED_LAN_HOST:8100", forKey: APIEndpointConfiguration.Keys.apiBaseURL)

        XCTAssertEqual(
            api([APIEndpointConfiguration.remoteArgument], device: true),
            URL(string: "http://REDACTED_LAN_HOST:8100")!
        )
        // 只覆盖了 api，eve 仍按常规规则解析
        XCTAssertEqual(eve(device: false), APIEndpointConfiguration.localEve)
    }

    func testMalformedOverrideFallsBackToTheNormalRule() {
        defaults.set("没有 scheme 的字符串", forKey: APIEndpointConfiguration.Keys.apiBaseURL)

        XCTAssertEqual(api(device: false), APIEndpointConfiguration.localAPI)
        XCTAssertEqual(api(device: true), APIEndpointConfiguration.remote)
    }

    /// 部署环境的 Nginx 按路径前缀分流，两个服务共用 80 端口，
    /// 因此 baseURL 相同也必须拼出各自正确的绝对地址。
    func testRemoteBaseURLsComposeDistinctPaths() {
        let environment = APIEnvironment(
            baseURL: api(device: true),
            eveBaseURL: eve(device: true),
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

    /// 本地栈是两个独立端口，不是共用一个。
    func testLocalBaseURLsUseSeparatePorts() {
        let environment = APIEnvironment(
            baseURL: api(device: false),
            eveBaseURL: eve(device: false),
            bearerToken: nil,
            accountID: nil,
            familyID: nil,
            pregnancyID: nil
        )

        XCTAssertEqual(
            environment.businessRequest(path: "/api/v1/health").url?.absoluteString,
            "http://127.0.0.1:8100/api/v1/health"
        )
        XCTAssertEqual(
            environment.eveRequest(path: "/eve/v1/session", method: "POST").url?.absoluteString,
            "http://127.0.0.1:2210/eve/v1/session"
        )
    }
}
