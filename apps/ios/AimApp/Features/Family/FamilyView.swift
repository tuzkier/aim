import SwiftUI

/// 家庭页：「我」卡片（进个人资料）、家庭卡片、成员与待处理邀请、家庭动态。
struct FamilyView: View {
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: FamilyStore
    @State private var showingInvite = false
    @State private var renamingTo: String?
    @State private var openInvitation: FamilyInvitation?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            familyContent
                .navigationTitle("家庭")
                .background(Color.aimCanvas)
                .refreshable { await store.load() }
                .task {
                    if store.snapshot == nil { await store.load() }
                }
                .navigationDestination(for: FamilyRoute.self) { route in
                    switch route {
                    case .profile:
                        ProfileView(store: store)
                    case let .member(member):
                        MemberDetailView(store: store, member: member)
                    case let .destination(target):
                        AgentDestinationView(target: target)
                    }
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
                .sheet(item: $openInvitation) { invitation in
                    InvitationDetailSheet(store: store, invitation: invitation)
                }
        }
    }

    @ViewBuilder
    private var familyContent: some View {
        if let family = store.snapshot {
            List {
                meCard
                familyCard(family)
                membersSection(family)
                FamilyActivitySection(store: store) { path.append(FamilyRoute.destination($0)) }
            }
            .scrollContentBackground(.hidden)
            .background(Color.aimCanvas)
            .listStyle(.insetGrouped)
        } else if store.isLoading {
            ProgressView("正在加载家庭")
        } else if let errorMessage = store.errorMessage {
            AimErrorState(message: errorMessage) { Task { await store.load() } }
        } else {
            AimEmptyState(title: "还没有家庭", message: "连接家庭后，计划和待办会在成员之间同步。")
        }
    }

    private var myself: FamilyMember? {
        guard let accountID = session.accountID else { return nil }
        return store.snapshot?.members.first { $0.accountID == accountID }
    }

    private var meCard: some View {
        Section {
            NavigationLink(value: FamilyRoute.profile) {
                HStack(spacing: AimMetrics.space12) {
                    MemberAvatar(name: myself?.displayName ?? "我", size: 44, highlighted: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text([myself?.displayName, myself?.role.displayName].compactMap { $0 }.uniqued().joined(separator: " · "))
                            .font(.body.weight(.semibold))
                        Text("个人资料与账号设置")
                            .font(.caption)
                            .foregroundStyle(Color.aimTextSecondary)
                    }
                }
                .padding(.vertical, AimMetrics.space4)
            }
            .accessibilityIdentifier("profile-entry")
        }
    }

    private func familyCard(_ family: FamilySnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: AimMetrics.space12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(family.name).font(.title2.weight(.semibold))
                    Spacer()
                    Button("改名") { renamingTo = family.name }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.aimAccent)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("family-rename")
                }
                if let pregnancy = store.pregnancy {
                    let elapsed = pregnancy.weeks * 7 + pregnancy.days
                    let remaining = max(0, PregnancyDateCalculator.standardGestationDays - elapsed)
                    Text("孕 \(pregnancy.weeks) 周 +\(pregnancy.days) 天 · 距预产期 \(remaining) 天")
                        .font(.subheadline)
                        .foregroundStyle(Color.aimTextSecondary)
                    ProgressView(value: Double(min(elapsed, 280)), total: 280)
                        .tint(Color.aimAccent)
                        .accessibilityLabel("孕期进度")
                } else {
                    Text("还没有孕期信息").font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                }
                HStack(spacing: -6) {
                    ForEach(family.members) { member in
                        MemberAvatar(name: member.displayName, size: 30, highlighted: member.accountID == session.accountID)
                            .overlay(Circle().stroke(Color.aimSurface, lineWidth: 2))
                    }
                    Button { showingInvite = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(Color.aimSurfaceSunken, in: Circle())
                            .overlay(Circle().stroke(Color.aimRail, style: StrokeStyle(lineWidth: 1, dash: [3])))
                            .foregroundStyle(Color.aimTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, AimMetrics.space12)
                    .accessibilityLabel("邀请家人")
                }
            }
            .aimCard()
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    private func membersSection(_ family: FamilySnapshot) -> some View {
        Section("家庭成员") {
            ForEach(family.members) { member in
                NavigationLink(value: FamilyRoute.member(member)) {
                    memberRow(member)
                }
                .accessibilityIdentifier("family-member-row")
            }
            ForEach(family.invitations) { invitation in
                Button { openInvitation = invitation } label: {
                    invitationRow(invitation)
                }
                .accessibilityIdentifier("family-invitation-row")
            }
            Button { showingInvite = true } label: {
                Label("邀请家人", systemImage: "person.badge.plus")
            }
            .accessibilityIdentifier("family-invite")
        }
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        HStack(spacing: AimMetrics.space12) {
            MemberAvatar(name: member.displayName, size: 36, highlighted: member.accountID == session.accountID)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName).font(.body.weight(.medium))
                Text(([member.nickname == nil ? nil : member.role.displayName, member.isAdmin ? "管理员" : nil]
                        .compactMap { $0 }).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.aimTextSecondary)
            }
            Spacer()
            if let count = store.openTaskCount(for: member.accountID), count > 0 {
                Text("\(count) 项待办").font(.caption).foregroundStyle(Color.aimTextSecondary)
            }
        }
    }

    private func invitationRow(_ invitation: FamilyInvitation) -> some View {
        HStack(spacing: AimMetrics.space12) {
            Image(systemName: "envelope")
                .frame(width: 36, height: 36)
                .background(Color.aimSurfaceSunken, in: Circle())
                .foregroundStyle(Color.aimTextSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.phoneMasked).foregroundStyle(Color.aimTextPrimary)
                Text("\(invitation.role.displayName) · \(invitation.isExpired ? "已过期" : "等待加入")")
                    .font(.caption)
                    .foregroundStyle(invitation.isExpired ? Color.aimDanger : Color.aimTextSecondary)
            }
            Spacer()
        }
    }
}

/// 家庭页内的跳转目标。
enum FamilyRoute: Hashable {
    case profile
    case member(FamilyMember)
    case destination(AgentDestination)

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }

    private var key: String {
        switch self {
        case .profile: "profile"
        case let .member(member): "member-\(member.accountID)"
        case let .destination(target): target.id
        }
    }
}

private extension Array where Element: Hashable {
    /// 称呼留空时 displayName 就是身份名，避免显示成「妈妈 · 妈妈」。
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
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
