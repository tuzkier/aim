import XCTest

@MainActor
final class TaskDetailStoreTests: XCTestCase {
    func testTaskDetailStartsFromServerVersion() {
        let task = TaskItem(id: UUID(), title: "核对材料", detail: nil, status: .todo, version: 3, dueAt: nil, scheduledFor: nil, assignedMemberID: nil)
        let store = TaskDetailStore(task: task, repository: nil)
        XCTAssertEqual(store.task.version, 3)
        XCTAssertEqual(store.task.status, .todo)
    }
}
