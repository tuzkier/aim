import Foundation
import Observation

struct DemoSessionResponse: Decodable, Sendable {
    let accountID: UUID
    let phone: String
    let familyID: UUID
    let pregnancyID: UUID?
    let role: FamilyRole
    let token: String

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case phone
        case familyID = "family_id"
        case pregnancyID = "pregnancy_id"
        case role
        case token
    }
}

private struct DemoSessionRequest: Encodable, Sendable {
    let phone: String
    let dueDate: String?

    enum CodingKeys: String, CodingKey {
        case phone
        case dueDate = "due_date"
    }
}

@MainActor
@Observable
final class OnboardingStore {
    var phone = "13800000002"
    var isSubmitting = false
    var errorMessage: String?

    func createDemoSession(using appSession: AppSessionStore) async {
        let normalizedPhone = phone.filter(\.isNumber)
        guard normalizedPhone.count >= 6 else {
            errorMessage = "请输入手机号。"
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let requestBody = DemoSessionRequest(
                phone: normalizedPhone,
                dueDate: nil,
            )
            let body = try JSONEncoder.aim.encode(requestBody)
            let request = appSession.environment.businessRequest(
                path: "/api/v1/auth/demo-session",
                method: "POST",
                body: body,
            )
            let (data, _) = try await URLSession.shared.aimData(for: request)
            let response = try JSONDecoder.aim.decode(DemoSessionResponse.self, from: data)
            appSession.configure(
                accountID: response.accountID,
                familyID: response.familyID,
                pregnancyID: response.pregnancyID,
                bearerToken: response.token,
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
