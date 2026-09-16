import XCTest
@testable import AimApp

/// 登录页此前只有手机号一个字段，点「开始体验」就进去了——服务端的
/// `demo-session` 免密即建即用。那个入口已经删掉，客户端要走真实的注册／登录。
///
/// 校验放在提交按钮上：后端也会拒，但让用户填完一整屏再收到一句失败，
/// 不如一开始就把按钮禁掉并说清缺什么。
final class AuthFormTests: XCTestCase {
    private func form(
        mode: AuthMode = .register,
        phone: String = "13800000002",
        password: String = "a-good-password",
        role: FamilyRole? = .mother,
        nickname: String = "",
        agreedToTerms: Bool = true
    ) -> AuthForm {
        AuthForm(
            mode: mode, phone: phone, password: password, role: role, nickname: nickname,
            agreedToTerms: agreedToTerms)
    }

    func testAValidRegistrationCanBeSubmitted() {
        XCTAssertTrue(form().canSubmit)
    }

    func testPhoneMustHaveEnoughDigits() {
        XCTAssertFalse(form(phone: "138").canSubmit)
        // 分隔符是用户自己敲的，不该因此判定手机号无效。
        XCTAssertTrue(form(phone: "138 0000 0002").canSubmit)
    }

    func testPasswordMustReachTheMinimumLength() {
        XCTAssertFalse(form(password: "short").canSubmit)
        XCTAssertTrue(form(password: String(repeating: "x", count: AuthForm.minPasswordLength)).canSubmit)
    }

    /// 角色以前写死成妈妈，爸爸和其他家人根本没有入口。现在必须显式选。
    func testRegistrationRequiresARole() {
        XCTAssertFalse(form(role: nil).canSubmit)
    }

    /// 登录不需要角色和称呼——那是注册时才定的东西。
    func testLoginDoesNotAskForARole() {
        XCTAssertTrue(form(mode: .login, role: nil).canSubmit)
    }

    /// 登录不校验密码长度：规则以后变严时，老密码仍然要能登进来。
    func testLoginAcceptsAnyNonEmptyPassword() {
        XCTAssertTrue(form(mode: .login, password: "old", role: nil).canSubmit)
        XCTAssertFalse(form(mode: .login, password: "", role: nil).canSubmit)
    }

    func testNicknameIsOptional() {
        XCTAssertTrue(form(nickname: "").canSubmit)
        XCTAssertTrue(form(nickname: "婆婆").canSubmit)
    }

    /// 送到服务端的手机号要去掉空格和连字符，和后端的 normalize_phone 对齐。
    func testSubmittedPhoneIsNormalised() {
        XCTAssertEqual(form(phone: "138-0000-0002").normalizedPhone, "13800000002")
    }

    /// 称呼只有空格时应当当作没填，而不是存一串空格进去。
    func testBlankNicknameIsSentAsNothing() {
        XCTAssertNil(form(nickname: "   ").submittedNickname)
        XCTAssertEqual(form(nickname: " 婆婆 ").submittedNickname, "婆婆")
    }

    /// App Store 与个人信息保护法都要求注册前明确同意。登录不用再点一次。
    func testRegistrationRequiresAgreeingToTerms() {
        XCTAssertFalse(form(agreedToTerms: false).canSubmit)
        XCTAssertTrue(form(agreedToTerms: true).canSubmit)
    }

    func testLoginDoesNotRequireAgreeingAgain() {
        XCTAssertTrue(form(mode: .login, role: nil, agreedToTerms: false).canSubmit)
    }
}
