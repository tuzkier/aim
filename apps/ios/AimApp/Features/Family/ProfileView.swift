import SwiftUI

/// 个人资料：我在家里的称呼和身份、全家共享的预产期、待处理的邀请、账号设置。
///
/// 从家庭页顶部的「我」卡片进来。账号分组的弹层（法律页、注销确认、密码页）挂在 List 上，
/// 不挂在 Section 上——原因见 `AccountSection` 的说明。
struct ProfileView: View {
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: FamilyStore
    @State private var editingMyself = false
    @State private var editingDueDate = false
    @State private var decidingInvitation: MyInvitation?
    @State private var legalPage: LegalPage?
    @State private var confirmingDeletion = false
    @State private var enteringPassword = false

    private var myself: FamilyMember? {
        guard let accountID = session.accountID else { return nil }
        return store.snapshot?.members.first { $0.accountID == accountID }
    }

    var body: some View {
        List {
            header
            Section("我在家里") {
                Button { editingMyself = true } label: {
                    LabeledContent("称呼", value: myself?.nickname?.isEmpty == false ? myself!.nickname! : "未设置")
                }
                .foregroundStyle(Color.aimTextPrimary)
                .accessibilityIdentifier("profile-edit-me")
                Button { editingMyself = true } label: {
                    LabeledContent("身份", value: myself?.role.displayName ?? "—")
                }
                .foregroundStyle(Color.aimTextPrimary)
            }

            pregnancySection

            if !store.myInvitations.isEmpty {
                Section {
                    ForEach(store.myInvitations) { invitation in
                        Button { decidingInvitation = invitation } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(invitation.inviterName)邀请你加入「\(invitation.familyName)」")
                                    .foregroundStyle(Color.aimTextPrimary)
                                Text("身份：\(invitation.role.displayName) · \(invitation.expiresAt, format: .dateTime.month().day()) 前有效")
                                    .font(.caption)
                                    .foregroundStyle(Color.aimTextSecondary)
                            }
                        }
                    }
                } header: {
                    Text("待处理邀请")
                }
            }

            AccountSection(legalPage: $legalPage, confirmingDeletion: $confirmingDeletion)
        }
        .scrollContentBackground(.hidden)
        .background(Color.aimCanvas)
        .listStyle(.insetGrouped)
        .navigationTitle("个人资料")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editingMyself) {
            EditMyMembershipSheet(store: store, member: myself)
        }
        .sheet(isPresented: $editingDueDate) {
            DueDateEditorSheet(store: store, currentDueDate: store.pregnancy?.dueDate)
        }
        .sheet(item: $decidingInvitation) { invitation in
            InvitationDecisionSheet(invitation: invitation, repository: store.repository) { Task { await store.load() } }
        }
        .accountPresentations(
            repository: store.repository,
            gateway: session.environment.baseURL,
            legalPage: $legalPage,
            confirmingDeletion: $confirmingDeletion,
            enteringPassword: $enteringPassword
        )
    }

    private var header: some View {
        Section {
            VStack(spacing: AimMetrics.space8) {
                MemberAvatar(name: myself?.displayName ?? "我", size: 64, highlighted: true)
                Text(myself?.displayName ?? "我").font(.title3.weight(.semibold))
                // 没设称呼时名字就是身份名，不再重复一遍。
                Text([myself?.nickname == nil ? nil : myself?.role.displayName, session.maskedPhone]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Color.aimTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AimMetrics.space8)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var pregnancySection: some View {
        Section {
            if let pregnancy = store.pregnancy {
                Button { editingDueDate = true } label: {
                    LabeledContent("预产期", value: pregnancy.dueDate.aimLongDate)
                }
                .foregroundStyle(Color.aimTextPrimary)
                .accessibilityIdentifier("profile-due-date")
                LabeledContent("当前孕周", value: "\(pregnancy.weeks) 周 +\(pregnancy.days) 天")
            } else {
                Text("还没有孕期信息").foregroundStyle(Color.aimTextSecondary)
            }
        } header: {
            Text("孕期（全家共享）")
        } footer: {
            if store.pregnancy != nil {
                Text("家里任何人都能修改，改动会记在家庭动态里。")
            }
        }
    }
}

/// 称呼首字的圆形头像。
struct MemberAvatar: View {
    let name: String
    var size: CGFloat = 36
    var highlighted = false

    var body: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(highlighted ? Color.aimAccent : Color.aimTextSecondary)
            .frame(width: size, height: size)
            .background(highlighted ? Color.aimAccentSoft : Color.aimSurfaceSunken, in: Circle())
            .accessibilityHidden(true)
    }
}

extension Date {
    /// 「2026年12月1日」
    var aimLongDate: String {
        formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
    }
}

extension AppSessionStore {
    /// 会话票里带着手机号（`aim.v1.<载荷>.<签名>`），打码后给个人资料页显示。
    var maskedPhone: String? {
        guard let bearerToken else { return nil }
        let parts = bearerToken.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var payload = String(parts[2]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONDecoder().decode([String: AnyCodableValue].self, from: data),
              case let .string(phone)? = claims["phone"], phone.count >= 7
        else { return nil }
        return "\(phone.prefix(3))****\(phone.suffix(4))"
    }
}

/// 只为从会话票里取出字符串字段。
enum AnyCodableValue: Decodable {
    case string(String)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value) } else { self = .other }
    }
}

/// 改自己的称呼和身份。注册时选错身份此前没有任何补救路径。
struct EditMyMembershipSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: FamilyStore
    let member: FamilyMember?

    @State private var nickname = ""
    @State private var role: FamilyRole = .mother
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("家里怎么称呼你", text: $nickname)
                        .accessibilityIdentifier("my-nickname-field")
                    Picker("你的身份", selection: $role) {
                        ForEach(FamilyRole.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .accessibilityIdentifier("my-role-picker")
                } footer: {
                    Text("称呼留空时，列表里会显示你的身份。")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.aimDanger) }
                }
            }
            .navigationTitle("我的信息")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("保存") { Task { await submit() } }
                            .accessibilityIdentifier("my-profile-save")
                    }
                }
            }
            .onAppear {
                nickname = member?.nickname ?? ""
                role = member?.role ?? .mother
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if await store.updateMyself(nickname: trimmed.isEmpty ? nil : trimmed, role: role) {
            dismiss()
        } else {
            errorMessage = store.errorMessage ?? "没改成，稍后再试。"
        }
    }
}
