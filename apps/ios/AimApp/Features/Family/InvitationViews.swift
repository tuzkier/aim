import SwiftUI

// MARK: - 发邀请

struct InviteMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: FamilyStore
    @State private var phone = ""
    @State private var role: FamilyRole = .father
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var sentTo: String?

    var body: some View {
        NavigationStack {
            Form {
                if let sentTo {
                    Section {
                        Label("邀请已发出", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.aimSuccess)
                        Text("让 TA 用 \(sentTo) 注册或登录 AIM，打开后就能看到邀请。邀请 7 天内有效。")
                            .font(.subheadline)
                            .foregroundStyle(Color.aimTextSecondary)
                    }
                } else {
                    Section {
                        TextField("手机号", text: $phone)
                            .keyboardType(.phonePad)
                            .accessibilityIdentifier("invite-phone")
                        Picker("身份", selection: $role) {
                            ForEach(FamilyRole.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                    } header: {
                        Text("邀请谁加入")
                    } footer: {
                        Text("对方用这个手机号注册或登录 AIM 后，会在 App 里看到邀请。")
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.aimDanger) }
                }
            }
            .navigationTitle("邀请家人")
            .toolbar {
                if sentTo == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }.disabled(isSubmitting)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Button("发送") { Task { await submit() } }
                                .disabled(phone.filter(\.isNumber).count < 6)
                                .accessibilityIdentifier("invite-send")
                        }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        if await store.invite(phone: phone, role: role) {
            sentTo = phone
        } else {
            errorMessage = store.errorMessage ?? "邀请没有发出去，稍后再试。"
        }
    }
}

// MARK: - 已发出的邀请

/// 点家庭页「等待加入」那一行：看详情、撤回，过期的可以重发。
struct InvitationDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: FamilyStore
    let invitation: FamilyInvitation
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var inviterName: String {
        store.snapshot?.members.first { $0.accountID == invitation.invitedBy }?.displayName ?? "家人"
    }

    private var canRevoke: Bool {
        session.accountID == invitation.invitedBy || store.snapshot?.admin?.accountID == session.accountID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("手机号", value: invitation.phoneMasked)
                    LabeledContent("身份", value: invitation.role.displayName)
                    LabeledContent("邀请人", value: inviterName)
                    LabeledContent(invitation.isExpired ? "已于" : "有效期至",
                                   value: invitation.expiresAt.formatted(.dateTime.month().day().hour().minute()))
                }
                if invitation.isExpired {
                    Section {
                        Text("对方 7 天内没有加入。手机号只显示打码后的，重发需要重新填写。")
                            .font(.subheadline)
                            .foregroundStyle(Color.aimTextSecondary)
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.aimDanger) }
                }
                if canRevoke && !invitation.isExpired {
                    Section {
                        Button("撤回邀请", role: .destructive) { Task { await revoke() } }
                            .disabled(isSubmitting)
                            .accessibilityIdentifier("invitation-revoke")
                    }
                }
            }
            .navigationTitle(invitation.isExpired ? "邀请已过期" : "等待加入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func revoke() async {
        isSubmitting = true
        defer { isSubmitting = false }
        if await store.revoke(invitation) {
            dismiss()
        } else {
            errorMessage = store.errorMessage
        }
    }
}

// MARK: - 发给我的邀请

/// 「老王邀请你以外婆的身份加入『我们的家』」：加入或暂不。
///
/// 直接调接口而不依赖 FamilyStore：填写预产期页（主界面之外）也要用它。
struct InvitationDecisionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSessionStore.self) private var session
    let invitation: MyInvitation
    let repository: BusinessRepositoryProtocol?
    /// 接受或暂不之后（成功时）回调，供外层刷新。
    var onFinish: () -> Void = {}
    @State private var confirmingJoin = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: AimMetrics.space16) {
                Image(systemName: "person.2.circle")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.aimAccent)
                    .padding(.top, AimMetrics.space20)
                Text("\(invitation.inviterName)邀请你以\(invitation.role.displayName)的身份加入「\(invitation.familyName)」")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("加入后，你们共享同一份孕期、待办和记录。")
                    .font(.subheadline)
                    .foregroundStyle(Color.aimTextSecondary)
                    .multilineTextAlignment(.center)
                if let reason = invitation.blockedReason, !invitation.canAccept {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(Color.aimDanger)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("invitation-blocked")
                }
                if let errorMessage {
                    Text(errorMessage).font(.subheadline).foregroundStyle(Color.aimDanger)
                }
                Spacer()
                if invitation.canAccept {
                    Button {
                        confirmingJoin = true
                    } label: {
                        Text("加入").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("invitation-accept")
                    Button("暂不") { Task { await decline() } }
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("invitation-decline")
                } else {
                    Button("知道了") {
                        Task { await decline() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, AimMetrics.space20)
            .padding(.bottom, AimMetrics.space20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.disabled(isSubmitting)
                }
            }
            .confirmationDialog("加入「\(invitation.familyName)」", isPresented: $confirmingJoin, titleVisibility: .visible) {
                Button("加入") { Task { await accept() } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("你现在的家庭和其中自动生成的孕期、待办会被删除。")
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isSubmitting)
    }

    private func accept() async {
        guard let repository else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let me = try await repository.acceptInvitation(id: invitation.id)
            session.switchFamily(familyID: me.familyID, pregnancyID: me.pregnancyID)
            session.familyNotice = "已加入「\(invitation.familyName)」"
            onFinish()
            dismiss()
        } catch {
            errorMessage = FamilyStore.message(for: error)
        }
    }

    private func decline() async {
        guard let repository else { dismiss(); return }
        isSubmitting = true
        defer { isSubmitting = false }
        // 不能接受的邀请点「知道了」也记为暂不：不再自动弹出，但仍留在个人资料页。
        if !invitation.wasDeclined {
            try? await repository.declineInvitation(id: invitation.id)
        }
        onFinish()
        dismiss()
    }
}

// MARK: - 自动弹出

/// 主界面与填写预产期页出现时查一次发给我的邀请，把还没「暂不」过的逐条弹出。
@MainActor
@Observable
final class InvitationPromptStore {
    var invitations: [MyInvitation] = []
    var current: MyInvitation?

    func check(using repository: BusinessRepositoryProtocol) async {
        guard let found = try? await repository.fetchMyInvitations() else { return }
        invitations = found
        if current == nil {
            current = found.first { !$0.wasDeclined }
        }
    }

    func next(using repository: BusinessRepositoryProtocol) async {
        current = nil
        await check(using: repository)
    }
}
