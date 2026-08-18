import SwiftUI

struct FamilyView: View {
    @Bindable var store: FamilyStore
    @State private var showingInvite = false

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
#if os(iOS)
            .listStyle(.insetGrouped)
#else
            .listStyle(.inset)
#endif
        } else if store.isLoading {
            ProgressView("正在加载家庭")
        } else {
            ContentUnavailableView("还没有家庭", systemImage: "person.2", description: Text(store.errorMessage ?? "连接家庭后，计划和待办会在成员之间同步。"))
        }
    }

    private func familyHeader(_ family: FamilySnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(family.name).font(.title2.weight(.semibold))
                Text("成员各自有账号，但共享同一份孕期计划和待办。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(member.role == .mother ? Color.aimAccent : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(member.role.displayName).font(.body.weight(.medium))
                Text(member.status == "active" ? "已加入" : "等待确认")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inviteSection: some View {
        Section {
            Button { showingInvite = true } label: {
                Label("邀请家庭成员", systemImage: "person.badge.plus")
            }
        }
    }
}

private struct InviteMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: FamilyStore
    @State private var phone = ""
    @State private var role: FamilyRole = .father
    @State private var isSubmitting = false

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
            }
            .navigationTitle("邀请成员")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") {
                        isSubmitting = true
                        Task {
                            if await store.invite(phone: phone, role: role) { dismiss() }
                            isSubmitting = false
                        }
                    }
                    .disabled(phone.count < 6 || isSubmitting)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
