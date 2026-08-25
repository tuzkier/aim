import Foundation

enum AuthMode: String, CaseIterable, Identifiable, Sendable {
    case login
    case register

    var id: String { rawValue }

    var title: String {
        switch self {
        case .login: "登录"
        case .register: "注册"
        }
    }
}

/// 登录／注册表单的规则。
///
/// 校验放在这里而不是视图里，是为了能不起模拟器就把规则测干净；
/// 也放在提交按钮上而不是等后端拒绝，因为让用户填完一整屏再收到一句失败，
/// 不如一开始就说清缺什么。
struct AuthForm: Equatable, Sendable {
    /// 与后端 `MIN_PASSWORD_LENGTH` 对齐。长度是密码强度里真正起作用的维度，
    /// 所以不要求大小写数字符号的组合。
    static let minPasswordLength = 8
    static let minPhoneDigits = 6

    var mode: AuthMode = .register
    var phone = ""
    var password = ""
    /// 只有注册要选；登录时角色早就定下来了。
    var role: FamilyRole?
    var nickname = ""

    /// 去掉用户敲的空格和连字符，和后端 `normalize_phone` 对齐。
    var normalizedPhone: String { phone.filter(\.isNumber) }

    /// 只有空格的称呼当作没填，而不是把一串空格存进去。
    var submittedNickname: String? {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var canSubmit: Bool {
        guard normalizedPhone.count >= Self.minPhoneDigits else { return false }
        switch mode {
        case .login:
            // 登录不校验长度：密码规则以后变严时，老密码仍然要能登进来。
            return !password.isEmpty
        case .register:
            return password.count >= Self.minPasswordLength && role != nil
        }
    }
}
