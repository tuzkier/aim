import Foundation
import Observation

@MainActor
@Observable
final class TodayStore {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var state: State = .idle
    var snapshot: TodaySnapshot?
    var repository: BusinessRepositoryProtocol?

    func load() async {
        guard let repository else { state = .failed(APIError.notConfigured.localizedDescription); return }
        state = .loading
        do {
            snapshot = try await repository.fetchToday()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func complete(_ task: TaskItem) async {
        guard let repository else { return }
        do {
            _ = try await repository.complete(task: task)
            await load()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    static func preview() -> TodayStore {
        let store = TodayStore()
        store.snapshot = TodaySnapshot(
            pregnancyID: UUID(),
            asOf: .now,
            weeks: 18,
            days: 2,
            priorityTask: TaskItem(id: UUID(), title: "预约下周的系统超声检查", detail: "建议提前确认医院和可用时间", status: .todo, version: 1, dueAt: .now.addingTimeInterval(86_400 * 3), scheduledFor: nil, assignedMemberID: nil, changedByActor: .system),
            upcomingTasks: [
                TaskItem(id: UUID(), title: "整理最近一次产检记录", detail: nil, status: .todo, version: 1, dueAt: .now.addingTimeInterval(86_400 * 6), scheduledFor: nil, assignedMemberID: nil, changedByActor: .system),
                TaskItem(id: UUID(), title: "确认杭州生育待遇材料", detail: nil, status: .todo, version: 1, dueAt: .now.addingTimeInterval(86_400 * 10), scheduledFor: nil, assignedMemberID: nil, changedByActor: .system),
            ],
            familyOpenTaskCount: 4
        )
        store.state = .loaded
        return store
    }
}
