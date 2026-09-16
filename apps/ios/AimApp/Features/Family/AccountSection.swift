import SwiftUI

/// 家庭页底部的「账号」分组：法律页、退出登录、注销。
///
/// 注销走两步确认：先说清 30 天规则，再要一次密码。密码不是为了防别人——
/// 手机已经解锁了——而是为了防手滑：这是全 App 唯一一个会让家人也丢数据的操作。
///
/// 弹层不挂在这里。`.sheet` / `.confirmationDialog` 挂在 `List` 里的 `Section` 上时，
/// 密码页会在确认框收起的同一帧被 List 的重绘打断——弹上来又立刻退回去。
/// 所以状态由 `FamilyView` 持有，弹层用 `accountPresentations` 挂在 `NavigationStack` 内、
/// `List` 之外，和其它几张 sheet 一个位置。
struct AccountSection: View {
    @Environment(AppSessionStore.self) private var session
    @Binding var legalPage: LegalPage?
    @Binding var confirmingDeletion: Bool

    var body: some View {
        Section("账号") {
            Button { legalPage = .privacy } label: { Label("隐私政策", systemImage: "hand.raised") }
                .accessibilityIdentifier("account-open-privacy")
            Button { legalPage = .terms } label: { Label("用户协议", systemImage: "doc.text") }
                .accessibilityIdentifier("account-open-terms")
            Button {
                session.clear()
                session.signOutNotice = "已退出登录"
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .accessibilityIdentifier("account-sign-out")
            Button(role: .destructive) { confirmingDeletion = true } label: {
                Label("注销账号", systemImage: "person.crop.circle.badge.xmark")
            }
            .accessibilityIdentifier("account-delete")
        }
    }
}

/// 「账号」分组的三张弹层：法律页、注销确认框、密码页。
private struct AccountPresentations: ViewModifier {
    @Environment(AppSessionStore.self) private var session
    let repository: BusinessRepositoryProtocol?
    let gateway: URL
    @Binding var legalPage: LegalPage?
    @Binding var confirmingDeletion: Bool
    @Binding var enteringPassword: Bool

    func body(content: Content) -> some View {
        content
            .legalPageSheet($legalPage, gateway: gateway)
            .confirmationDialog(
                "注销账号",
                isPresented: $confirmingDeletion,
                titleVisibility: .visible
            ) {
                // confirmationDialog 的按钮桥接成 UIAlertAction，accessibilityIdentifier 会丢；
                // XCUITest 要用标题查：app.buttons["继续注销"]。
                Button("继续注销", role: .destructive) { enteringPassword = true }
                    .accessibilityIdentifier("account-delete-confirm")
                Button("取消", role: .cancel) {}
            } message: {
                Text("账号会立即停用。30 天内重新登录可以撤销；30 天后账号和你的个人数据将被删除。")
            }
            .sheet(isPresented: $enteringPassword) {
                DeleteAccountSheet(repository: repository) {
                    enteringPassword = false
                    session.clear()
                    session.signOutNotice = "注销申请已提交。30 天内重新登录可撤销，之后数据将被删除。"
                }
            }
    }
}

extension View {
    func accountPresentations(
        repository: BusinessRepositoryProtocol?,
        gateway: URL,
        legalPage: Binding<LegalPage?>,
        confirmingDeletion: Binding<Bool>,
        enteringPassword: Binding<Bool>
    ) -> some View {
        modifier(AccountPresentations(
            repository: repository,
            gateway: gateway,
            legalPage: legalPage,
            confirmingDeletion: confirmingDeletion,
            enteringPassword: enteringPassword
        ))
    }
}

private struct DeleteAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let repository: BusinessRepositoryProtocol?
    let onDeleted: () -> Void

    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("输入密码以确认", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("account-delete-password")
                } footer: {
                    Text("提交后会退回登录页。")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.aimDanger) }
                }
            }
            .navigationTitle("确认注销")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("注销", role: .destructive) { Task { await submit() } }
                            .disabled(password.isEmpty)
                            .accessibilityIdentifier("account-delete-submit")
                    }
                }
            }
        }
        .presentationDetents([.medium])
        // 提交中下滑关掉 sheet，请求照样发出去，人却以为没提交：和「取消」一样，此时不许关。
        .interactiveDismissDisabled(isSubmitting)
    }

    private func submit() async {
        guard let repository else {
            errorMessage = "网络还没准备好，稍后再试。"
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await repository.requestAccountDeletion(password: password)
            onDeleted()
        } catch let error as APIError {
            if case let .http(status, _) = error, status == 401 {
                errorMessage = "密码不对"
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
