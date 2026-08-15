import Foundation
import Observation

@MainActor
@Observable
final class AppSessionStore {
    var accountID: UUID?
    var familyID: UUID?
    var pregnancyID: UUID?
    var bearerToken: String?
    var isOffline = false

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        accountID = UUID(uuidString: defaults.string(forKey: Keys.accountID) ?? "")
        familyID = UUID(uuidString: defaults.string(forKey: Keys.familyID) ?? "")
        pregnancyID = UUID(uuidString: defaults.string(forKey: Keys.pregnancyID) ?? "")
        bearerToken = keychain.read(Keys.bearerToken)
    }

    var isConfigured: Bool {
        accountID != nil && familyID != nil && bearerToken != nil
    }

    var environment: APIEnvironment {
        APIEnvironment(
            baseURL: URL(string: defaults.string(forKey: Keys.apiBaseURL) ?? "http://127.0.0.1:8100")!,
            eveBaseURL: URL(string: defaults.string(forKey: Keys.eveBaseURL) ?? "http://127.0.0.1:2210")!,
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
        static let apiBaseURL = "aim.apiBaseURL"
        static let eveBaseURL = "aim.eveBaseURL"
    }
}
