import Foundation
import Observation

@MainActor
@Observable
final class FamilyStore {
    var snapshot: FamilySnapshot?
    var isLoading = false
    var errorMessage: String?
    var repository: BusinessRepositoryProtocol?
    var openTaskCounts: [UUID: Int] = [:]
    /// 全家共享的孕期（预产期、当前孕周）。还没建孕期时为 nil。
    var pregnancy: PregnancySummary?
    var activity: [FamilyActivityItem] = []
    var isLoadingActivity = false
    /// 发给我的、还能接受的邀请（个人资料页「待处理邀请」）。
    var myInvitations: [MyInvitation] = []
    /// 家庭接口返回 403：我已经不在这个家庭里了（被移出）。由外层据此切回自己的新家庭。
    var lostMembership = false
    private var activityCursor: String?
    private var activityExhausted = false

    var hasMoreActivity: Bool { !activityExhausted }

    func openTaskCount(for accountID: UUID) -> Int? { openTaskCounts[accountID] }

    func load() async {
        guard let repository else { errorMessage = APIError.notConfigured.localizedDescription; return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await repository.fetchFamily()
            errorMessage = nil
        } catch {
            if case let APIError.http(status, _) = error, status == 403 {
                lostMembership = true
                return
            }
            errorMessage = error.localizedDescription
        }
        pregnancy = try? await repository.fetchPregnancy()
        myInvitations = (try? await repository.fetchMyInvitations()) ?? []
        await reloadActivity()
        if let plan = try? await repository.fetchPlan() {
            openTaskCounts = Dictionary(
                grouping: plan.tasks.filter(\.isOpen).compactMap(\.assignedMemberID),
                by: { $0 }
            ).mapValues(\.count)
        }
    }

    func invite(phone: String, role: FamilyRole) async -> Bool {
        guard let repository else { errorMessage = APIError.notConfigured.localizedDescription; return false }
        do { try await repository.invite(phone: phone, role: role); await load(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    func rename(to name: String) async -> Bool {
        guard let repository else {
            errorMessage = APIError.notConfigured.localizedDescription
            return false
        }
        do { try await repository.renameFamily(to: name); await load(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    func updateMyself(nickname: String?, role: FamilyRole?) async -> Bool {
        guard let repository else {
            errorMessage = APIError.notConfigured.localizedDescription
            return false
        }
        do {
            try await repository.updateMyMembership(nickname: nickname, role: role)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: 家庭动态

    func reloadActivity() async {
        activityCursor = nil
        activityExhausted = false
        activity = []
        await loadMoreActivity()
    }

    /// 滑到底时加载更早的一页。
    func loadMoreActivity() async {
        guard let repository, !activityExhausted, !isLoadingActivity else { return }
        isLoadingActivity = true
        defer { isLoadingActivity = false }
        guard let page = try? await repository.fetchActivity(before: activityCursor) else { return }
        activity += page.items
        activityCursor = page.nextBefore
        activityExhausted = page.nextBefore == nil
    }

    // MARK: 预产期、邀请、成员

    func updateDueDate(_ dueDate: Date) async -> Bool {
        await perform { repository in
            pregnancy = try await repository.updateDueDate(dueDate)
            await reloadActivity()
        }
    }

    func revoke(_ invitation: FamilyInvitation) async -> Bool {
        await perform { repository in
            try await repository.revokeInvitation(id: invitation.id)
            await load()
        }
    }

    func remove(_ member: FamilyMember) async -> Bool {
        await perform { repository in
            try await repository.removeMember(accountID: member.accountID)
            await load()
        }
    }

    /// 退出家庭。成功返回新家庭，由调用方切换会话。
    func leave() async -> MeSnapshot? {
        var result: MeSnapshot?
        _ = await perform { repository in result = try await repository.leaveFamily() }
        return result
    }

    func memberDetail(_ member: FamilyMember) async -> MemberDetail? {
        guard let repository else { return nil }
        do { return try await repository.fetchMemberDetail(accountID: member.accountID) }
        catch { errorMessage = error.localizedDescription; return nil }
    }

    private func perform(_ work: (BusinessRepositoryProtocol) async throws -> Void) async -> Bool {
        guard let repository else {
            errorMessage = APIError.notConfigured.localizedDescription
            return false
        }
        do {
            try await work(repository)
            errorMessage = nil
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// 服务端的中文说明（409/422 的 message）比通用错误更有用，优先给用户看。
    static func message(for error: Error) -> String {
        if case let APIError.http(_, body) = error,
           let data = body.data(using: .utf8),
           let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
            return payload.error.message
        }
        return error.localizedDescription
    }

    private struct ErrorPayload: Decodable {
        struct Inner: Decodable { let message: String }
        let error: Inner
    }

    static func preview() -> FamilyStore {
        let store = FamilyStore()
        store.snapshot = FamilySnapshot(id: UUID(), name: "我们的家", members: [
            FamilyMember(accountID: UUID(), role: .mother, nickname: "阿敏", status: "active", joinedAt: .now),
            FamilyMember(accountID: UUID(), role: .father, nickname: nil, status: "active", joinedAt: .now),
        ])
        return store
    }
}
