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

    /// 测试一律注入假的部署地址。真实值来自不进版本库的 xcconfig，构建机上不保证存在；
    /// 而且断言里写死真实主机名，等于把它又抄进了公开仓库一份。
    private let stubRemote = URL(string: "http://remote.test")!

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
        APIEndpointConfiguration.apiBaseURL(
            defaults: defaults, arguments: args, isDeviceBuild: device, remote: stubRemote
        )
    }

    private func eve(_ args: [String] = [], device: Bool) -> URL {
        APIEndpointConfiguration.eveBaseURL(
            defaults: defaults, arguments: args, isDeviceBuild: device, remote: stubRemote
        )
    }

    /// 这条是这次改动的核心：测试跑在模拟器上，就不该碰到部署环境。
    func testSimulatorBuildDefaultsToLocalStack() {
        XCTAssertEqual(api(device: false), APIEndpointConfiguration.localAPI)
        XCTAssertEqual(eve(device: false), APIEndpointConfiguration.localEve)
    }

    func testDeviceBuildDefaultsToDeployedEnvironment() {
        XCTAssertEqual(api(device: true), stubRemote)
        XCTAssertEqual(eve(device: true), stubRemote)
    }

    /// 真正跑起来时用的那个无参版本，在模拟器上必须解析成本地。
    /// 这条守的是「测试自己」——它此刻就跑在模拟器里。
    ///
    /// 它同时守着 `remote` 的惰性：这里没有注入假地址，走的是默认的
    /// `APIEndpointConfiguration.remote`。构建机上没配 xcconfig 时那个属性会
    /// `fatalError`，所以一旦有人把 `@autoclosure` 改回普通参数，这条会当场崩掉。
    func testProductionCallPathResolvesLocallyWhileTestsRun() {
        XCTAssertEqual(
            APIEndpointConfiguration.apiBaseURL(defaults: defaults, arguments: []),
            APIEndpointConfiguration.localAPI,
            "测试进程连的必须是本地栈，不能是部署环境"
        )
        XCTAssertFalse(APIEndpointConfiguration.isDeviceBuild, "测试跑在模拟器上")
    }

    /// 偶尔要拿模拟器验部署环境，留一个显式开关。
    func testRemoteArgumentPointsASimulatorAtTheDeployedEnvironment() {
        let args = [APIEndpointConfiguration.remoteArgument]
        XCTAssertEqual(api(args, device: false), stubRemote)
        XCTAssertEqual(eve(args, device: false), stubRemote)
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
        defaults.set("http://192.0.2.10:8100", forKey: APIEndpointConfiguration.Keys.apiBaseURL)

        XCTAssertEqual(
            api([APIEndpointConfiguration.remoteArgument], device: true),
            URL(string: "http://192.0.2.10:8100")!
        )
        // 只覆盖了 api，eve 仍按常规规则解析
        XCTAssertEqual(eve(device: false), APIEndpointConfiguration.localEve)
    }

    func testMalformedOverrideFallsBackToTheNormalRule() {
        defaults.set("没有 scheme 的字符串", forKey: APIEndpointConfiguration.Keys.apiBaseURL)

        XCTAssertEqual(api(device: false), APIEndpointConfiguration.localAPI)
        XCTAssertEqual(api(device: true), stubRemote)
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
            "http://remote.test/api/v1/health"
        )
        XCTAssertEqual(
            environment.eveRequest(path: "/eve/v1/session", method: "POST").url?.absoluteString,
            "http://remote.test/eve/v1/session"
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
