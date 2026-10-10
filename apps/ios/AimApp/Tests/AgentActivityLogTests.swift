import XCTest
@testable import AimApp

@MainActor
final class AgentActivityLogTests: XCTestCase {
    private func actionResult(
        toolName: String,
        summary: String,
        data: [String: Any] = [:]
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

    /// 翻资料目录、读资料、看时间也都是只读的，同样不该进台账。
    func testLibraryAndTimeToolsDoNotEnterTheActivityLog() {
        let store = AgentStore()

        for tool in ["list_library", "get_library_entry", "get_current_time"] {
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
        XCTAssertEqual(entry.undoTarget, .tasks([taskID]))
    }

    func testRememberHasARecordUndoTargetButForgettingIsNotUndoable() {
        let store = AgentStore()
        let id = UUID()
        store.consume(actionResult(toolName: "remember", summary: "已记住：短答",
                                   data: ["record_id": id.uuidString.lowercased(), "text": "短答"]))
        XCTAssertEqual(store.activityLog.first?.undoTarget, .records([id]))
        XCTAssertEqual(store.activityLog.first?.title, "已记住「短答」")
        let count = store.activityLog.count
        store.consume(actionResult(toolName: "forget_memory", summary: "已遗忘：短答"))
        XCTAssertEqual(store.activityLog.count, count)
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
        XCTAssertEqual(store.activityLog[0].undoTarget, .records([recordID]))
    }

    /// 批量建待办的结果是 `tasks` 数组。此前按 `[String: String]` 解码，遇到数组整个
    /// 解析静默失败，撤销入口就没了。
    func testBatchCreatedTasksAreAllUndoTargets() {
        let store = AgentStore()
        let first = UUID(), second = UUID()

        store.consume(
            actionResult(
                toolName: "create_task",
                summary: "已添加 2 项待办",
                data: [
                    "tasks": [
                        ["task_id": first.uuidString, "title": "买钙片"],
                        ["task_id": second.uuidString, "title": "约 NT"],
                    ],
                    "failed": [],
                ]
            )
        )

        XCTAssertEqual(store.activityLog.count, 1)
        XCTAssertEqual(store.activityLog[0].title, "已添加 2 项待办")
        XCTAssertEqual(store.activityLog[0].undoTarget, .tasks([first, second]))
    }

    /// 只有一条时服务端把字段平铺到外层，同时仍带 `tasks` 数组。
    func testSingleCreatedTaskWithFlattenedFieldsKeepsItsTitle() {
        let store = AgentStore()
        let taskID = UUID()

        store.consume(
            actionResult(
                toolName: "create_task",
                summary: "已添加待办：买钙片",
                data: [
                    "tasks": [["task_id": taskID.uuidString, "title": "买钙片"]],
                    "failed": [],
                    "task_id": taskID.uuidString,
                    "title": "买钙片",
                ]
            )
        )

        XCTAssertEqual(store.activityLog[0].title, "已添加待办「买钙片」")
        XCTAssertEqual(store.activityLog[0].undoTarget, .tasks([taskID]))
    }

    /// 产检报告连同攒下的问题一次建好，撤销要整批删掉。
    func testCheckupReportUndoesEveryRecordItCreated() {
        let store = AgentStore()
        let report = UUID(), question = UUID()

        store.consume(
            actionResult(
                toolName: "create_checkup_report",
                summary: "已记下 10月3日产检报告，并攒了 1 个想问医生的问题",
                data: [
                    "record_id": report.uuidString,
                    "record_ids": [report.uuidString.lowercased(), question.uuidString.lowercased()],
                    "title": "10月3日 产检报告",
                    "question_count": 1,
                ]
            )
        )

        XCTAssertEqual(store.activityLog.count, 1)
        XCTAssertEqual(store.activityLog[0].title, "已记下「10月3日 产检报告」")
        XCTAssertEqual(store.activityLog[0].undoTarget, .records([report, question]))
    }

    /// 带图片的记录结果里 `attachment_count` 是整数，不能让整个解析失败。
    func testRecordResultWithAnIntegerFieldStillHasAnUndoTarget() {
        let store = AgentStore()
        let recordID = UUID()

        store.consume(
            actionResult(
                toolName: "create_record",
                summary: "已记录",
                data: ["record_id": recordID.uuidString, "attachment_count": 2]
            )
        )

        XCTAssertEqual(store.activityLog[0].undoTarget, .records([recordID]))
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
            canUndo: true, undoTarget: .tasks([taskID])
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
            canUndo: true, undoTarget: .records([recordID])
        )
        store.activityLog = [activity]

        await store.undoDirectly(activity)

        XCTAssertEqual(repository.deletedRecordIDs, [recordID])
    }

    /// 报告和它的问题整批删：问题先删，报告最后，和服务端撤销的顺序一致。
    func testUndoingACheckupReportDeletesQuestionsBeforeTheReport() async {
        let repository = SpyRepository()
        let store = AgentStore()
        store.repository = repository
        let report = UUID(), first = UUID(), second = UUID()
        let activity = AgentActivity(
            id: UUID(), title: "已记下「10月3日 产检报告」", occurredAt: .now,
            canUndo: true, undoTarget: .records([report, first, second])
        )
        store.activityLog = [activity]

        await store.undoDirectly(activity)

        XCTAssertEqual(repository.deletedRecordIDs, [second, first, report])
        XCTAssertTrue(store.activityLog.isEmpty)
    }

    func testUndoingBatchCreatedTasksDeletesEveryOne() async {
        let repository = SpyRepository()
        let store = AgentStore()
        store.repository = repository
        let first = UUID(), second = UUID()
        let activity = AgentActivity(
            id: UUID(), title: "已添加 2 项待办", occurredAt: .now,
            canUndo: true, undoTarget: .tasks([first, second])
        )
        store.activityLog = [activity]

        await store.undoDirectly(activity)

        XCTAssertEqual(Set(repository.deletedTaskIDs), [first, second])
        XCTAssertTrue(store.activityLog.isEmpty)
    }

    /// 删到一半失败：已删掉的不再留在撤销目标里，重试只删剩下的。
    func testPartiallyFailedUndoKeepsOnlyWhatIsLeft() async {
        let repository = SpyRepository()
        let store = AgentStore()
        store.repository = repository
        let report = UUID(), question = UUID()
        repository.failingRecordIDs = [report]
        let activity = AgentActivity(
            id: UUID(), title: "已记下「10月3日 产检报告」", occurredAt: .now,
            canUndo: true, undoTarget: .records([report, question])
        )
        store.activityLog = [activity]

        await store.undoDirectly(activity)

        XCTAssertEqual(repository.deletedRecordIDs, [question])
        XCTAssertEqual(store.activityLog.count, 1)
        XCTAssertEqual(store.activityLog[0].undoTarget, .records([report]))
    }

    /// 已经被别人删掉的（404）算撤销成功，否则这条台账永远撤不掉。
    func testAlreadyDeletedRecordsCountAsUndone() async {
        let repository = SpyRepository()
        let store = AgentStore()
        store.repository = repository
        let gone = UUID(), question = UUID()
        repository.missingRecordIDs = [gone]
        let activity = AgentActivity(
            id: UUID(), title: "已记下「10月3日 产检报告」", occurredAt: .now,
            canUndo: true, undoTarget: .records([gone, question])
        )
        store.activityLog = [activity]

        await store.undoDirectly(activity)

        XCTAssertEqual(repository.deletedRecordIDs, [question])
        XCTAssertTrue(store.activityLog.isEmpty)
    }

    /// 删除失败时台账条目要留着，否则撤销入口消失、数据却还在。
    func testFailedUndoKeepsTheEntry() async throws {
        let repository = SpyRepository()
        repository.shouldFail = true
        let store = AgentStore()
        store.repository = repository
        let activity = AgentActivity(
            id: UUID(), title: "已添加待办「买钙片」", occurredAt: .now,
            canUndo: true, undoTarget: .tasks([UUID()])
        )
        store.activityLog = [activity]

        await store.undoDirectly(activity)

        XCTAssertEqual(store.activityLog.count, 1)
    }
}

@MainActor
final class TaskDetailDeleteTests: XCTestCase {
    private let task = TaskItem(
        id: UUID(), title: "加错的待办", detail: nil, status: .todo, version: 1,
        dueAt: nil, scheduledFor: nil, assignedMemberID: nil, changedByActor: .agent
    )

    func testDeletingCallsTheRepositoryWithTheTaskID() async {
        let repository = SpyRepository()
        let store = TaskDetailStore(task: task, repository: repository)

        let deleted = await store.delete()

        XCTAssertTrue(deleted)
        XCTAssertEqual(repository.deletedTaskIDs, [task.id])
    }

    func testAFailedDeleteReportsAnErrorAndKeepsThePage() async {
        let repository = SpyRepository()
        repository.shouldFail = true
        let store = TaskDetailStore(task: task, repository: repository)

        let deleted = await store.delete()

        XCTAssertFalse(deleted)
        XCTAssertNotNil(store.errorMessage)
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

    var failingRecordIDs: Set<UUID> = []
    var missingRecordIDs: Set<UUID> = []

    func deleteRecord(recordID: UUID) async throws {
        if shouldFail || failingRecordIDs.contains(recordID) { throw APIError.invalidResponse }
        if missingRecordIDs.contains(recordID) { throw APIError.http(status: 404, body: "") }
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
    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem { throw APIError.notConfigured }
    func complete(task: TaskItem) async throws -> TaskItem { throw APIError.notConfigured }
    func delay(task: TaskItem, until: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func schedule(task: TaskItem, at: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem { throw APIError.notConfigured }
    func invite(phone: String, role: FamilyRole) async throws { throw APIError.notConfigured }

    // 这两个替身不涉及家庭编辑，实现成空操作即可；
    // 真要用到时会因为断言不成立而暴露，而不是被静默吞掉。
    func renameFamily(to name: String) async throws {}
    func updateMyMembership(nickname: String?, role: FamilyRole?) async throws {}
    func requestAccountDeletion(password: String) async throws { throw APIError.notConfigured }
}
