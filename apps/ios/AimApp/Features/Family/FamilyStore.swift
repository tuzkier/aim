import Foundation
import Observation

@MainActor
@Observable
final class FamilyStore {
    var snapshot: FamilySnapshot?
    var isLoading = false
    var errorMessage: String?
    var repository: BusinessRepositoryProtocol?

    func load() async {
        guard let repository else { errorMessage = APIError.notConfigured.localizedDescription; return }
        isLoading = true
        defer { isLoading = false }
        do { snapshot = try await repository.fetchFamily(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func invite(phone: String, role: FamilyRole) async -> Bool {
        guard let repository else { errorMessage = APIError.notConfigured.localizedDescription; return false }
        do { try await repository.invite(phone: phone, role: role); await load(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    static func preview() -> FamilyStore {
        let store = FamilyStore()
        store.snapshot = FamilySnapshot(id: UUID(), name: "我们的家", members: [
            FamilyMember(accountID: UUID(), role: .mother, status: "active", joinedAt: .now),
            FamilyMember(accountID: UUID(), role: .father, status: "active", joinedAt: .now),
        ])
        return store
    }
}
