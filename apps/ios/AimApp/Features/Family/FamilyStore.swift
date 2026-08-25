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

    func openTaskCount(for accountID: UUID) -> Int? { openTaskCounts[accountID] }

    func load() async {
        guard let repository else { errorMessage = APIError.notConfigured.localizedDescription; return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await repository.fetchFamily()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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

    static func preview() -> FamilyStore {
        let store = FamilyStore()
        store.snapshot = FamilySnapshot(id: UUID(), name: "我们的家", members: [
            FamilyMember(accountID: UUID(), role: .mother, nickname: "阿敏", status: "active", joinedAt: .now),
            FamilyMember(accountID: UUID(), role: .father, nickname: nil, status: "active", joinedAt: .now),
        ])
        return store
    }
}
