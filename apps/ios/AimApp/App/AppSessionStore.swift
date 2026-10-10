import Foundation
import Observation

/// 启动参数开关。UI 测试都以 `-reset-session` 启动，借它识别测试环境；
/// 显式传 `-ui-testing` 也算。
enum LaunchFlags {
    static var isUITesting: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-reset-session") || arguments.contains("-ui-testing")
    }
}

@MainActor
@Observable
final class AppSessionStore {
    var accountID: UUID?
    var familyID: UUID?
    var pregnancyID: UUID?
    var bearerToken: String?
    var isOffline = false
    /// 退出或注销后回到登录页要说一句话；登录页读一次就清掉。不持久化。
    var signOutNotice: String?
    /// 登录时服务端撤销了注销申请，进首页提示一次。
    var welcomeBackNotice: String?
    /// 换了家庭（加入、退出、被移出）后提示一次，如「你已不在『我们的家』里」。
    var familyNotice: String?

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    /// 观察者随 store 一起释放时自动注销。`deinit` 在 @MainActor 类里是
    /// nonisolated，碰不到 main-actor 属性，所以把注销挪进这个包装的 deinit。
    private final class ObserverToken: @unchecked Sendable {
        private let token: any NSObjectProtocol
        init(_ token: any NSObjectProtocol) { self.token = token }
        deinit { NotificationCenter.default.removeObserver(token) }
    }

    private var expiryObserver: ObserverToken?

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        accountID = UUID(uuidString: defaults.string(forKey: Keys.accountID) ?? "")
        familyID = UUID(uuidString: defaults.string(forKey: Keys.familyID) ?? "")
        pregnancyID = UUID(uuidString: defaults.string(forKey: Keys.pregnancyID) ?? "")
        bearerToken = keychain.read(Keys.bearerToken)
        if ProcessInfo.processInfo.arguments.contains("-reset-session") {
            clear()
        }
        expiryObserver = ObserverToken(
            NotificationCenter.default.addObserver(
                forName: .aimSessionExpired, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleSessionExpired() }
            }
        )
    }

    /// 服务端不认这张票了。清掉本地会话——根视图看到 `isConfigured == false`
    /// 就会回到登录页，用户重新进一次就恢复了。
    ///
    /// 家庭和孕期 ID 也要一并清：服务端账号没了，那两个 ID 指向的东西同样不存在，
    /// 留着只会让下一次请求继续 404/401。
    func handleSessionExpired() {
        guard isConfigured else { return }
        clear()
    }

    var isConfigured: Bool {
        accountID != nil && familyID != nil && bearerToken != nil
    }

    var environment: APIEnvironment {
        APIEnvironment(
            baseURL: APIEndpointConfiguration.apiBaseURL(defaults: defaults),
            eveBaseURL: APIEndpointConfiguration.eveBaseURL(defaults: defaults),
            bearerToken: bearerToken,
            accountID: accountID,
            familyID: familyID,
            pregnancyID: pregnancyID
        )
    }

    func configure(accountID: UUID, familyID: UUID, pregnancyID: UUID?, bearerToken: String) {
        self.accountID = accountID
        self.familyID = familyID
        self.pregnancyID = pregnancyID
        self.bearerToken = bearerToken
        defaults.set(accountID.uuidString, forKey: Keys.accountID)
        defaults.set(familyID.uuidString, forKey: Keys.familyID)
        if let pregnancyID {
            defaults.set(pregnancyID.uuidString, forKey: Keys.pregnancyID)
        } else {
            defaults.removeObject(forKey: Keys.pregnancyID)
        }
        try? keychain.write(bearerToken, for: Keys.bearerToken)
    }

    /// 换到另一个家庭：接受邀请、退出、被移出之后。孕期可能为空（新的空家庭）。
    func switchFamily(familyID: UUID, pregnancyID: UUID?) {
        self.familyID = familyID
        self.pregnancyID = pregnancyID
        defaults.set(familyID.uuidString, forKey: Keys.familyID)
        if let pregnancyID {
            defaults.set(pregnancyID.uuidString, forKey: Keys.pregnancyID)
        } else {
            defaults.removeObject(forKey: Keys.pregnancyID)
        }
    }

    func setPregnancyID(_ pregnancyID: UUID) {
        self.pregnancyID = pregnancyID
        defaults.set(pregnancyID.uuidString, forKey: Keys.pregnancyID)
    }

    func clear() {
        accountID = nil
        familyID = nil
        pregnancyID = nil
        bearerToken = nil
        defaults.removeObject(forKey: Keys.accountID)
        defaults.removeObject(forKey: Keys.familyID)
        defaults.removeObject(forKey: Keys.pregnancyID)
        keychain.delete(Keys.bearerToken)
    }

    private enum Keys {
        static let accountID = "aim.accountID"
        static let familyID = "aim.familyID"
        static let pregnancyID = "aim.pregnancyID"
        static let bearerToken = "aim.bearerToken"
    }
}
