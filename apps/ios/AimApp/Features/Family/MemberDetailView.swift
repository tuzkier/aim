import SwiftUI

/// 一位家人：TA 负责的待办（可直接勾选完成）、TA 最近记的、退出或移出。
struct MemberDetailView: View {
    @Environment(AppSessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: FamilyStore
    let member: FamilyMember
    @State private var detail: MemberDetail?
    @State private var completing: UUID?
    @State private var editingMyself = false
    @State private var confirmingLeave = false
    @State private var confirmingRemove = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var isMe: Bool { member.accountID == session.accountID }
    private var iAmAdmin: Bool { store.snapshot?.admin?.accountID == session.accountID }
    private var familyName: String { store.snapshot?.name ?? "家庭" }
    private var canLeave: Bool { (store.snapshot?.members.count ?? 0) > 1 }

    var body: some View {
        List {
            Section {
                VStack(spacing: AimMetrics.space8) {
                    MemberAvatar(name: member.displayName, size: 64, highlighted: isMe)
                    HStack(spacing: AimMetrics.space8) {
                        Text(member.displayName).font(.title3.weight(.semibold))
                        if member.isAdmin {
                            Text("管理员")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.aimAccentSoft, in: Capsule())
                                .foregroundStyle(Color.aimAccent)
                        }
                    }
                    Text([member.nickname == nil ? nil : member.role.displayName,
                          member.joinedAt.map { "\($0.aimLongDate)加入" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Color.aimTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AimMetrics.space8)
            }
            .listRowBackground(Color.clear)

            Section(isMe ? "我负责的待办" : "TA 负责的待办") {
                if let tasks = detail?.openTasks {
                    if tasks.isEmpty {
                        Text(isMe ? "没有指派给你的待办" : "没有指派给 TA 的待办").foregroundStyle(Color.aimTextSecondary)
                    }
                    ForEach(tasks) { task in
                        HStack(spacing: AimMetrics.space12) {
                            Button { Task { await complete(task) } } label: {
                                Image(systemName: completing == task.id ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(completing == task.id ? Color.aimSuccess : Color.aimRail)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("完成「\(task.title)」")
                            NavigationLink(value: FamilyRoute.destination(.task(task))) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                    if let due = task.dueAt {
                                        Text(due, format: .dateTime.month().day())
                                            .font(.caption).foregroundStyle(Color.aimTextSecondary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }

            Section(isMe ? "我最近记的" : "TA 最近记的") {
                if let records = detail?.recentRecords {
                    if records.isEmpty {
                        Text("还没有记录").foregroundStyle(Color.aimTextSecondary)
                    }
                    ForEach(records) { record in
                        NavigationLink(value: FamilyRoute.destination(.record(record))) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(record.displayTitle, systemImage: record.type.symbolName)
                                Text(record.occurredAt, format: .dateTime.month().day())
                                    .font(.caption).foregroundStyle(Color.aimTextSecondary)
                            }
                        }
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(Color.aimDanger) }
            }

            actions
        }
        .scrollContentBackground(.hidden)
        .background(Color.aimCanvas)
        .listStyle(.insetGrouped)
        .navigationTitle(member.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $editingMyself) {
            EditMyMembershipSheet(store: store, member: member)
        }
        .confirmationDialog("退出「\(familyName)」？", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("退出家庭", role: .destructive) { Task { await leave() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后：你负责的待办会变成未指派；你的私密记录会被删除；你需要新建孕期，或接受别人的邀请。")
        }
        .confirmationDialog("把 \(member.displayName) 移出家庭？", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("移出家庭", role: .destructive) { Task { await remove() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("移出后 TA 负责的待办会变成未指派，TA 的私密记录会被删除。")
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isMe {
            Section {
                Button("改称呼和身份") { editingMyself = true }
                    .accessibilityIdentifier("member-edit-me")
                if canLeave {
                    Button("退出家庭", role: .destructive) { confirmingLeave = true }
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("member-leave")
                }
            }
        } else if iAmAdmin {
            Section {
                Button("移出家庭", role: .destructive) { confirmingRemove = true }
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("member-remove")
            }
        }
    }

    private func reload() async {
        detail = await store.memberDetail(member)
    }

    private func complete(_ task: TaskItem) async {
        guard let repository = store.repository else { return }
        completing = task.id
        defer { completing = nil }
        do {
            _ = try await repository.complete(task: task)
            NotificationCenter.default.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["task"]])
            await reload()
            await store.reloadActivity()
        } catch {
            errorMessage = FamilyStore.message(for: error)
        }
    }

    private func leave() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let name = familyName
        if let me = await store.leave() {
            session.switchFamily(familyID: me.familyID, pregnancyID: me.pregnancyID)
            session.familyNotice = "你已退出「\(name)」"
        } else {
            errorMessage = store.errorMessage
        }
    }

    private func remove() async {
        isSubmitting = true
        defer { isSubmitting = false }
        if await store.remove(member) {
            dismiss()
        } else {
            errorMessage = store.errorMessage
        }
    }
}
