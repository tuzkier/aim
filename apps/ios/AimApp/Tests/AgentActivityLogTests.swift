import XCTest
@testable import AimApp

@MainActor
final class AgentActivityLogTests: XCTestCase {
    private func actionResult(
        toolName: String,
        summary: String,
        data: [String: String] = [:]
    ) -> EveEvent {
        let payload: [String: Any] = [
            "result": [
                "callId": "call_1",
                "kind": "tool-result",
                "toolName": toolName,
                "output": [
                    "operationId": UUID().uuidString,
                    "status": "completed",
                    "summary": summary,
                    "data": data,
                ],
            ],
            "sequence": 0,
            "status": "completed",
        ]
        return EveEvent(
            type: .actionResult,
            rawType: "action.result",
            eventID: UUID().uuidString,
            streamIndex: 0,
            data: try! JSONSerialization.data(withJSONObject: payload)
        )
    }

    /// 只读工具不修改任何东西，却会被记成「已更新家庭计划 · 可撤销」。
    /// 用户只是问了一句，台账上却出现一条撤销入口，指向并不存在的变更。
    func testReadOnlyToolsDoNotEnterTheActivityLog() {
        let store = AgentStore()

        for tool in ["get_pregnancy_context", "list_tasks", "list_records", "get_guidance"] {
            store.consume(actionResult(toolName: tool, summary: "已读取"))
        }

        XCTAssertTrue(store.activityLog.isEmpty)
    }

    func testCreatingATaskIsLoggedWithItsTitleAndAnUndoTarget() {
        let store = AgentStore()
        let taskID = UUID()

        store.consume(
            actionResult(
                toolName: "create_task",
                summary: "已添加待办：买孕妇钙片",
                data: ["task_id": taskID.uuidString, "title": "买孕妇钙片"]
            )
        )

        XCTAssertEqual(store.activityLog.count, 1)
        let entry = store.activityLog[0]
        XCTAssertEqual(entry.title, "已添加待办「买孕妇钙片」")
        XCTAssertEqual(entry.undoTarget, .task(taskID))
    }

    func testCreatingARecordIsLoggedWithAnUndoTarget() {
        let store = AgentStore()
        let recordID = UUID()

        store.consume(
            actionResult(
                toolName: "create_record",
                summary: "已记录",
                data: ["record_id": recordID.uuidString]
            )
        )

        XCTAssertEqual(store.activityLog.count, 1)
        XCTAssertEqual(store.activityLog[0].undoTarget, .record(recordID))
    }

    /// 修改既有任务仍走既有的 undo_operation 语义，本次改动不该动它。
    func testUpdatingATaskKeepsTheExistingSummary() {
        let store = AgentStore()

        store.consume(actionResult(toolName: "update_task", summary: "已完成任务：产检"))

        XCTAssertEqual(store.activityLog.count, 1)
        XCTAssertEqual(store.activityLog[0].title, "已更新家庭计划")
        XCTAssertNil(store.activityLog[0].undoTarget)
    }

    func testMostRecentEntryComesFirst() {
        let store = AgentStore()

        store.consume(
            actionResult(
                toolName: "create_task",
                summary: "一",
                data: ["task_id": UUID().uuidString, "title": "第一条"]
            )
        )
        store.consume(
            actionResult(
                toolName: "create_task",
                summary: "二",
                data: ["task_id": UUID().uuidString, "title": "第二条"]
            )
        )

        XCTAssertEqual(store.activityLog.map(\.title), ["已添加待办「第二条」", "已添加待办「第一条」"])
    }
}

@MainActor
final class AgentUndoTests: XCTestCase {
    /// 撤销「Agent 新建」必须直接删掉那条数据，而不是发一句「撤销上一次计划变更」
    /// 让模型自己去挑工具——实测模型会转而反问，撤销就落空了。
    func testUndoingACreatedTaskDeletesItDirectly() async throws {
        let repository = SpyRepository()
        let store = AgentStore()
        store.repository = repository
        let taskID = UUID()
        let activity = AgentActivity(
            id: UUID(), title: "已添加待办「买钙片」", occurredAt: .now,
            canUndo: true, undoTarget: .task(taskID)
        )
        store.activityLog = [activity]

        await store.undoDirectly(activity)

        XCTAssertEqual(repository.deletedTaskIDs, [taskID])
        XCTAssertTrue(store.activityLog.isEmpty)
    }

    func testUndoingACreatedRecordDeletesIt() async throws {
        let repository = SpyRepository()
        let store = AgentStore()
        store.repository = repository
        let recordID = UUID()
        let activity = AgentActivity(
            id: UUID(), title: "已记录", occurredAt: .now,
            canUndo: true, undoTarget: .record(recordID)
        )
        store.activityLog = [activity]

        await store.undoDirectly(activity)

        XCTAssertEqual(repository.deletedRecordIDs, [recordID])
    }

    /// 删除失败时台账条目要留着，否则撤销入口消失、数据却还在。
    func testFailedUndoKeepsTheEntry() async throws {
        let repository = SpyRepository()
        repository.shouldFail = true
        let store = AgentStore()
        store.repository = repository
        let activity = AgentActivity(
            id: UUID(), title: "已添加待办「买钙片」", occurredAt: .now,
            canUndo: true, undoTarget: .task(UUID())
        )
        store.activityLog = [activity]

        await store.undoDirectly(activity)

        XCTAssertEqual(store.activityLog.count, 1)
    }
}

private final class SpyRepository: BusinessRepositoryProtocol, @unchecked Sendable {
    var deletedTaskIDs: [UUID] = []
    var deletedRecordIDs: [UUID] = []
    var shouldFail = false

    func deleteTask(taskID: UUID) async throws {
        if shouldFail { throw APIError.invalidResponse }
        deletedTaskIDs.append(taskID)
    }

    func fetchSafetyRules() async throws -> [SafetyRule] { [] }
    func fetchContentCollection(_ name: String) async throws -> ContentCollection {
        ContentCollection(id: name, source: "test", sourceURL: "", items: [])
    }

    func deleteRecord(recordID: UUID) async throws {
        if shouldFail { throw APIError.invalidResponse }
        deletedRecordIDs.append(recordID)
    }

    func fetchToday() async throws -> TodaySnapshot { throw APIError.notConfigured }
    func fetchPlan() async throws -> PlanSnapshot { throw APIError.notConfigured }
    func fetchFamily() async throws -> FamilySnapshot { throw APIError.notConfigured }
    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot { throw APIError.notConfigured }
    func createPregnancy(dueDate: Date) async throws -> UUID { throw APIError.notConfigured }
    func createRecord(draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func createTaskFromRecord(record: RecordItem, title: String, description: String?, dueAt: Date?) async throws -> TaskItem { throw APIError.notConfigured }
    func complete(task: TaskItem) async throws -> TaskItem { throw APIError.notConfigured }
    func delay(task: TaskItem, until: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func schedule(task: TaskItem, at: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem { throw APIError.notConfigured }
    func invite(phone: String, role: FamilyRole) async throws { throw APIError.notConfigured }

    // 这两个替身不涉及家庭编辑，实现成空操作即可；
    // 真要用到时会因为断言不成立而暴露，而不是被静默吞掉。
    func renameFamily(to name: String) async throws {}
    func updateMyMembership(nickname: String?, role: FamilyRole?) async throws {}
}
