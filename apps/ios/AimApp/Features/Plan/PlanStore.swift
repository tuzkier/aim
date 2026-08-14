import Foundation
import Observation

@MainActor
@Observable
final class PlanStore {
    var snapshot: PlanSnapshot?
    var isLoading = false
    var errorMessage: String?
    var repository: BusinessRepositoryProtocol?

    func load() async {
        guard let repository else { errorMessage = APIError.notConfigured.localizedDescription; return }
        isLoading = true
        defer { isLoading = false }
        do { snapshot = try await repository.fetchPlan(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    static func preview() -> PlanStore {
        let store = PlanStore()
        store.snapshot = PlanSnapshot(id: UUID(), pregnancyID: UUID(), version: 1, tasks: [
            TaskItem(id: UUID(), title: "预约下周的系统超声检查", detail: nil, status: .todo, version: 1, dueAt: .now.addingTimeInterval(86_400 * 3), scheduledFor: nil, assignedMemberID: nil),
            TaskItem(id: UUID(), title: "整理最近一次产检记录", detail: nil, status: .scheduled, version: 1, dueAt: .now.addingTimeInterval(86_400 * 7), scheduledFor: .now.addingTimeInterval(86_400 * 7), assignedMemberID: nil),
            TaskItem(id: UUID(), title: "确认杭州生育待遇材料", detail: nil, status: .completed, version: 2, dueAt: .now.addingTimeInterval(86_400 * 10), scheduledFor: nil, assignedMemberID: nil),
        ])
        return store
    }
}
