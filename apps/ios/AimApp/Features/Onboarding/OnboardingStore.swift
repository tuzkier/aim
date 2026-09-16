import Foundation
import Observation

struct SessionResponse: Decodable, Sendable {
    let accountID: UUID
    let phone: String
    let familyID: UUID
    let pregnancyID: UUID?
    let role: FamilyRole
    let token: String
    /// 登录时服务端顺手撤销了注销申请。旧服务端没有这个字段，缺省为 false。
    let deletionCancelled: Bool

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case phone
        case familyID = "family_id"
        case pregnancyID = "pregnancy_id"
        case role
        case token
        case deletionCancelled = "deletion_cancelled"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try container.decode(UUID.self, forKey: .accountID)
        phone = try container.decode(String.self, forKey: .phone)
        familyID = try container.decode(UUID.self, forKey: .familyID)
        pregnancyID = try container.decodeIfPresent(UUID.self, forKey: .pregnancyID)
        role = try container.decode(FamilyRole.self, forKey: .role)
        token = try container.decode(String.self, forKey: .token)
        deletionCancelled = try container.decodeIfPresent(Bool.self, forKey: .deletionCancelled) ?? false
    }
}

private struct RegisterRequest: Encodable, Sendable {
    let phone: String
    let password: String
    let role: String
    let nickname: String?
}

private struct LoginRequest: Encodable, Sendable {
    let phone: String
    let password: String
}

/// 注册与登录。
///
/// 此前这里调的是 `demo-session`：给个手机号就即建即用，无任何凭证。那个端点
/// 已经从服务端删除——开放注册的前提下留着免密通道，密码就只是装饰。
@MainActor
@Observable
final class OnboardingStore {
    var form = AuthForm()
    var isSubmitting = false
    var errorMessage: String?

    func submit(using appSession: AppSessionStore) async {
        guard form.canSubmit else {
            errorMessage = validationHint
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let request = try makeRequest(using: appSession)
            let (data, _) = try await URLSession.shared.aimData(for: request)
            let response = try JSONDecoder.aim.decode(SessionResponse.self, from: data)
            appSession.configure(
                accountID: response.accountID,
                familyID: response.familyID,
                pregnancyID: response.pregnancyID,
                bearerToken: response.token,
            )
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func makeRequest(using appSession: AppSessionStore) throws -> URLRequest {
        switch form.mode {
        case .register:
            let body = try JSONEncoder.aim.encode(
                RegisterRequest(
                    phone: form.normalizedPhone,
                    password: form.password,
                    role: (form.role ?? .mother).rawValue,
                    nickname: form.submittedNickname,
                )
            )
            return appSession.environment.businessRequest(
                path: "/api/v1/auth/register", method: "POST", body: body)
        case .login:
            let body = try JSONEncoder.aim.encode(
                LoginRequest(phone: form.normalizedPhone, password: form.password)
            )
            return appSession.environment.businessRequest(
                path: "/api/v1/auth/login", method: "POST", body: body)
        }
    }

    /// 后端的原始错误串对用户没有意义。这几档是用户真正能据此行动的。
    private func message(for error: Error) -> String {
        guard let apiError = error as? APIError, case let .http(status, _) = apiError else {
            return error.localizedDescription
        }
        switch status {
        case 401: return "手机号或密码不对"
        case 409: return "这个手机号已经注册过了，直接登录吧"
        case 422: return "手机号或密码不符合要求"
        case 429: return "尝试太频繁了，过一分钟再试"
        default: return apiError.localizedDescription
        }
    }

    private var validationHint: String {
        if form.normalizedPhone.count < AuthForm.minPhoneDigits { return "请输入手机号" }
        if form.mode == .register, form.password.count < AuthForm.minPasswordLength {
            return "密码至少 \(AuthForm.minPasswordLength) 位"
        }
        if form.password.isEmpty { return "请输入密码" }
        if form.mode == .register, form.role == nil { return "请选择你在家里的身份" }
        if form.mode == .register, !form.agreedToTerms { return "请先阅读并同意用户协议和隐私政策" }
        return "请检查填写的内容"
    }
}
