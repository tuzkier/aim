import Foundation
import Observation

@MainActor
@Observable
final class TaskDetailStore {
    var task: TaskItem
    var isSaving = false
    var errorMessage: String?
    let repository: BusinessRepositoryProtocol?

    init(task: TaskItem, repository: BusinessRepositoryProtocol?) {
        self.task = task
        self.repository = repository
    }

    func complete() async -> Bool {
        guard let repository else { return false }
        isSaving = true
        defer { isSaving = false }
        do { task = try await repository.complete(task: task); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    func delay(until date: Date) async -> Bool {
        guard let repository else { return false }
        isSaving = true
        defer { isSaving = false }
        do { task = try await repository.delay(task: task, until: date); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
}
