import Foundation

/// 后端地址的解析规则。
///
/// 优先级从高到低：
/// 1. `UserDefaults` 里的 `aim.apiBaseURL` / `aim.eveBaseURL`（手动覆盖，最高优先）
/// 2. `-local` 启动参数：强制走本地 Compose 栈
/// 3. `-remote` 启动参数：强制走部署环境（拿模拟器验线上时用）
/// 4. 默认：**真机连部署环境，模拟器连本地**
///
/// 第 4 条以前是反的——默认远端、`-local` 才本地。代价是模拟器和 UI 测试全都打在
/// 部署环境上，两天就在生产库里堆了 253 个测试账号。判据换成编译期的
/// `targetEnvironment(simulator)` 而不是启动参数：参数会忘记加，而忘记的代价是
/// 脏数据默默写进生产库。装到真机上的包是拿去用的，那才需要真后端。
///
/// 部署环境的 Nginx 按路径前缀分流，`/api/v1/*` 和 `/eve/v1/*` 共用同一个 80 端口，
/// 所以两个 baseURL 相同；本地 Compose 则是两个独立端口。
///
/// - Warning: 第 1 条的覆盖值会**静默压过**其余规则，而且模拟器的偏好域独立于 App 容器，
///   卸载重装都清不掉，App 内部调用 `removeObject` 也删不掉（值位于 App 无权写入的
///   外层域）。如果 App 连到了意料之外的地方，先查这个：
///   ```
///   xcrun simctl spawn booted defaults read com.aim.pregnancy
///   xcrun simctl spawn booted defaults delete com.aim.pregnancy
///   ```
enum APIEndpointConfiguration {
    static let remote = URL(string: "http://REDACTED_HOST/")!
    /// 127.0.0.1 在模拟器上指向 Mac 本机，所以模拟器能直接连开发机的 Compose 栈。
    /// 真机上它指向手机自己，连不到——真机要连本地栈得用第 1 条覆盖成 Mac 的局域网 IP。
    static let localAPI = URL(string: "http://127.0.0.1:8100")!
    static let localEve = URL(string: "http://127.0.0.1:2210")!

    /// 这个包是不是装在真机上。编译期决定，运行时改不了。
    static var isDeviceBuild: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    static func apiBaseURL(
        defaults: UserDefaults,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isDeviceBuild: Bool = APIEndpointConfiguration.isDeviceBuild
    ) -> URL {
        resolve(
            override: defaults.string(forKey: Keys.apiBaseURL),
            local: localAPI,
            arguments: arguments,
            isDeviceBuild: isDeviceBuild
        )
    }

    static func eveBaseURL(
        defaults: UserDefaults,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isDeviceBuild: Bool = APIEndpointConfiguration.isDeviceBuild
    ) -> URL {
        resolve(
            override: defaults.string(forKey: Keys.eveBaseURL),
            local: localEve,
            arguments: arguments,
            isDeviceBuild: isDeviceBuild
        )
    }

    private static func resolve(
        override: String?,
        local: URL,
        arguments: [String],
        isDeviceBuild: Bool
    ) -> URL {
        if let override, let url = URL(string: override), url.scheme != nil {
            return url
        }
        // 两个参数都给时以 -local 为准：把流量拉回本机是更保守的那个选择。
        if arguments.contains(localArgument) { return local }
        if arguments.contains(remoteArgument) { return remote }
        return isDeviceBuild ? remote : local
    }

    static let localArgument = "-local"
    static let remoteArgument = "-remote"

    enum Keys {
        static let apiBaseURL = "aim.apiBaseURL"
        static let eveBaseURL = "aim.eveBaseURL"
    }
}
