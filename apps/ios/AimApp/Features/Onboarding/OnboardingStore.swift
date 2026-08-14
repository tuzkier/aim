import Foundation
import Observation

@MainActor
@Observable
final class OnboardingStore {
    var accountID = ""
    var familyID = ""
    var pregnancyID = ""
    var bearerToken = ""
    var errorMessage: String?

    func connect(using session: AppSessionStore) -> Bool {
        guard let accountID = UUID(uuidString: accountID),
              let familyID = UUID(uuidString: familyID),
              let pregnancyID = UUID(uuidString: pregnancyID),
              !bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请填写有效的账号、家庭、孕期 ID 和会话 Token。"
            return false
        }
        session.configure(accountID: accountID, familyID: familyID, pregnancyID: pregnancyID, bearerToken: bearerToken)
        return true
    }
}
