import SwiftUI

struct FamilyView: View {
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: FamilyStore
    @State private var showingInvite = false
    @State private var renamingTo: String?
    @State private var editingMyself = false

    var body: some View {
        NavigationStack {
            familyContent
            .navigationTitle("家庭")
            .background(Color.aimCanvas)
            .refreshable { await store.load() }
            .task {
                if store.snapshot == nil { await store.load() }
            }
            .sheet(isPresented: $showingInvite) {
                InviteMemberSheet(store: store)
            }
            .sheet(item: Binding(
                get: { renamingTo.map(RenameTarget.init(name:)) },
                set: { renamingTo = $0?.name }
            )) { target in
                RenameFamilySheet(store: store, name: target.name)
            }
            .sheet(isPresented: $editingMyself) {
                EditMyMembershipSheet(store: store, member: myself)
            }
        }
    }

    @ViewBuilder
    private var familyContent: some View {
        if let family = store.snapshot {
            List {
                familyHeader(family)
                familyMembers(family)
                inviteSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.aimCanvas)
#if os(iOS)
            .listStyle(.insetGrouped)
#else
            .listStyle(.inset)
#endif
        } else if store.isLoading {
            ProgressView("正在加载家庭")
        } else if let errorMessage = store.errorMessage {
            AimErrorState(message: errorMessage) { Task { await store.load() } }
        } else {
            AimEmptyState(title: "还没有家庭", message: "连接家庭后，计划和待办会在成员之间同步。")
        }
    }

    private func familyHeader(_ family: FamilySnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(family.name).font(.title2.weight(.semibold))
                    Spacer()
                    Button("改名") { renamingTo = family.name }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.aimAccent)
                        .accessibilityIdentifier("family-rename")
                }
                Text("成员各自有账号，但共享同一份孕期计划和待办。")
                    .font(.subheadline)
                    .foregroundStyle(Color.aimTextSecondary)
            }
            .aimCard()
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))
    }

    private func familyMembers(_ family: FamilySnapshot) -> some View {
        Section("家庭成员") {
            ForEach(family.members) { member in
                familyMemberRow(member)
            }
        }
    }

    private func familyMemberRow(_ member: FamilyMember) -> some View {
        HStack(spacing: 12) {
            Image(systemName: member.role == .mother ? "person.crop.circle.fill" : "person.circle.fill")
                .font(.title2)
                .foregroundStyle(member.role == .mother ? Color.aimAccent : Color.aimTextSecondary)
            VStack(alignment: .leading, spacing: 3) {
                // 称呼在前，角色退到副标题：两个「其他家人」只显示角色的话，
                // 在列表里完全分不出谁是谁。
                Text(member.displayName).font(.body.weight(.medium))
                Text(member.nickname == nil
                     ? statusText(member)
                     : "\(member.role.displayName) · \(statusText(member))")
                    .font(.caption)
                    .foregroundStyle(Color.aimTextSecondary)
            }
        }
        .accessibilityIdentifier("family-member-row")
    }

    private func statusText(_ member: FamilyMember) -> String {
        let base = member.status == "active" ? "已加入" : "等待确认"
        guard let count = store.openTaskCount(for: member.accountID), count > 0 else { return base }
        return "\(base) · \(count) 项待办"
    }

    private var inviteSection: some View {
        Section {
            Button { editingMyself = true } label: {
                Label("改我的称呼和身份", systemImage: "person.text.rectangle")
            }
            .accessibilityIdentifier("family-edit-me")

            Button { showingInvite = true } label: {
                Label("邀请家庭成员", systemImage: "person.badge.plus")
            }
        } footer: {
            // 只能改自己：改别人需要一套「谁能改谁」的权限模型，当前没有需求支撑它。
            Text("只能修改你自己的称呼和身份。")
        }
    }

    /// 当前登录的这个人。找不到时（数据还没加载完）用一个空壳，
    /// 让编辑面板仍然能打开并填写。
    private var myself: FamilyMember? {
        guard let accountID = session.accountID else { return nil }
        return store.snapshot?.members.first { $0.accountID == accountID }
    }
}

private struct InviteMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: FamilyStore
    @State private var phone = ""
    @State private var role: FamilyRole = .father
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("邀请谁加入") {
                    TextField("手机号", text: $phone)
#if os(iOS)
                        .keyboardType(.phonePad)
#endif
                    Picker("账号身份", selection: $role) {
                        ForEach(FamilyRole.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.aimDanger) }
                }
            }
            .navigationTitle("邀请成员")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("发送") { Task { await submit() } }
                            .disabled(phone.filter(\.isNumber).count < 6)
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
            dismiss()
        } else {
            errorMessage = store.errorMessage ?? "邀请没有发出去，稍后再试。"
        }
    }
}

/// `sheet(item:)` 需要一个 Identifiable，而家庭名是普通字符串。
private struct RenameTarget: Identifiable {
    let name: String
    var id: String { name }
}

private struct RenameFamilySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: FamilyStore
    @State var name: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("家庭名") {
                    TextField("家庭名", text: $name)
                        .accessibilityIdentifier("family-name-field")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.aimDanger) }
                }
            }
            .navigationTitle("改家庭名")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("保存") { Task { await submit() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("family-name-save")
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
        if await store.rename(to: name.trimmingCharacters(in: .whitespaces)) {
            dismiss()
        } else {
            errorMessage = store.errorMessage ?? "没改成，稍后再试。"
        }
    }
}

/// 改自己的称呼和身份。注册时选错身份此前没有任何补救路径。
private struct EditMyMembershipSheet: View {
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
