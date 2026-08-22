import Foundation

/// 后端地址的解析规则。
///
/// 优先级从高到低：
/// 1. `UserDefaults` 里的 `aim.apiBaseURL` / `aim.eveBaseURL`（手动覆盖，最高优先）
/// 2. `-local` 启动参数：指向 `make dev` 起的本地 Compose 栈
/// 3. 默认：部署在阿里云的验证环境
///
/// 验证环境的 Nginx 按路径前缀分流，`/api/v1/*` 和 `/eve/v1/*` 共用同一个 80 端口，
/// 所以两个 baseURL 相同；本地 Compose 则是两个独立端口。
///
/// - Warning: 第 1 条的覆盖值会**静默压过**默认值，而且模拟器的偏好域独立于 App 容器，
///   卸载重装都清不掉，App 内部调用 `removeObject` 也删不掉（值位于 App 无权写入的
///   外层域）。如果 App 明明该连服务器却连了别处，先查这个：
///   ```
///   xcrun simctl spawn booted defaults read com.aim.pregnancy
///   xcrun simctl spawn booted defaults delete com.aim.pregnancy
///   ```
enum APIEndpointConfiguration {
    static let remote = URL(string: "http://REDACTED_HOST/")!
    static let localAPI = URL(string: "http://127.0.0.1:8100")!
    static let localEve = URL(string: "http://127.0.0.1:2210")!

    static func apiBaseURL(
        defaults: UserDefaults,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> URL {
        resolve(
            override: defaults.string(forKey: Keys.apiBaseURL),
            local: localAPI,
            arguments: arguments
        )
    }

    static func eveBaseURL(
        defaults: UserDefaults,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> URL {
        resolve(
            override: defaults.string(forKey: Keys.eveBaseURL),
            local: localEve,
            arguments: arguments
        )
    }

    private static func resolve(override: String?, local: URL, arguments: [String]) -> URL {
        if let override, let url = URL(string: override), url.scheme != nil {
            return url
        }
        return arguments.contains(localArgument) ? local : remote
    }

    static let localArgument = "-local"

    enum Keys {
        static let apiBaseURL = "aim.apiBaseURL"
        static let eveBaseURL = "aim.eveBaseURL"
    }
}
