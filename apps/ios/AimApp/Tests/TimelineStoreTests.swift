import XCTest
@testable import AimApp

@MainActor
final class TimelineStoreTests: XCTestCase {
    func testFilterAllKeepsTasksAndRecords() {
        XCTAssertTrue(TimelineFilter.all.accepts(entryKind: .task))
        XCTAssertTrue(TimelineFilter.all.accepts(entryKind: .record(.checkup)))
    }

    func testFilterTasksExcludesRecords() {
        XCTAssertTrue(TimelineFilter.tasks.accepts(entryKind: .task))
        XCTAssertFalse(TimelineFilter.tasks.accepts(entryKind: .record(.note)))
    }

    func testFilterCheckupOnlyAcceptsCheckupRecords() {
        XCTAssertFalse(TimelineFilter.checkup.accepts(entryKind: .task))
        XCTAssertTrue(TimelineFilter.checkup.accepts(entryKind: .record(.checkup)))
        XCTAssertFalse(TimelineFilter.checkup.accepts(entryKind: .record(.symptom)))
    }

    func testAssigneeNameResolvesFromFamilyMembers() {
        let store = TimelineStore.preview()
        let motherID = store.familyMembers.first { $0.role == .mother }?.accountID
        XCTAssertEqual(store.assigneeName(for: motherID), "妈妈")
        XCTAssertNil(store.assigneeName(for: nil))
        XCTAssertNil(store.assigneeName(for: UUID()))
    }

    func testCompleteWithoutRepositoryReturnsFalse() async {
        let store = TimelineStore()
        let task = TaskItem(id: UUID(), title: "核对材料", detail: nil, status: .todo, version: 1,
                             dueAt: nil, scheduledFor: nil, assignedMemberID: nil, changedByActor: .system)
        let result = await store.complete(task)
        XCTAssertFalse(result)
    }

    // MARK: - 首页派生属性

    private let calendar = PregnancyDateCalculator.calendar

    /// 2026-09-14 周一 10:30，孕 22 周 + 6 天。
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 10, minute: 30))!
    }

    private func at(_ day: Int, _ hour: Int = 9, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func task(_ title: String, due: Date?, status: TaskStatus = .todo) -> TaskItem {
        TaskItem(id: UUID(), title: title, detail: nil, status: status, version: 1,
                 dueAt: due, scheduledFor: nil, assignedMemberID: nil, changedByActor: .system)
    }

    private func record(_ occurred: Date, title: String) -> RecordItem {
        RecordItem(id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
                   type: .note, occurredAt: occurred, visibility: .family, title: title, content: nil,
                   structuredData: .note, attachmentRefs: [], createdAt: occurred, updatedAt: occurred)
    }

    private func makeStore(tasks: [TaskItem], records: [RecordItem] = [], weeks: Int = 22, days: Int = 6) -> TimelineStore {
        let store = TimelineStore()
        store.now = now
        store.today = now
        store.tasks = tasks
        store.records = records
        store.lastMenstrualPeriod = TimelineBuilder.lastMenstrualPeriod(asOf: now, weeks: weeks, days: days)
        store.rebuild()
        return store
    }

    func testStageNameFollowsWeek() {
        XCTAssertEqual(makeStore(tasks: [], weeks: 13, days: 6).stageName, "孕早期")
        XCTAssertEqual(makeStore(tasks: [], weeks: 14, days: 0).stageName, "孕中期")
        XCTAssertEqual(makeStore(tasks: [], weeks: 27, days: 6).stageName, "孕中期")
        XCTAssertEqual(makeStore(tasks: [], weeks: 28, days: 0).stageName, "孕晚期")
    }

    func testFocusPrefersOverdueThenTodayThenEarliestUpcoming() {
        let overdue = task("逾期", due: at(12))
        let today = task("今天", due: at(14, 20))
        let later = task("下周", due: at(20))
        XCTAssertEqual(makeStore(tasks: [later, today, overdue]).focusTask?.title, "逾期")
        XCTAssertEqual(makeStore(tasks: [later, today]).focusTask?.title, "今天")
        XCTAssertEqual(makeStore(tasks: [later]).focusTask?.title, "下周")
        XCTAssertNil(makeStore(tasks: [task("完了", due: at(14), status: .completed)]).focusTask)
    }

    func testTodayTasksIncludeOverdueAndUndatedButExcludeFocus() {
        let overdue = task("逾期", due: at(12))
        let today = task("今天", due: at(14, 20))
        let undated = task("没定时间", due: nil)
        let done = task("已完成", due: at(14), status: .completed)
        let tomorrow = task("明天", due: at(15))
        let store = makeStore(tasks: [undated, tomorrow, today, done, overdue])

        XCTAssertEqual(store.focusTask?.title, "逾期")
        XCTAssertEqual(store.todayTasks.map(\.title), ["今天", "没定时间"])
        XCTAssertEqual(store.overdueCount, 0, "逾期的那条已经是焦点，不重复计")
        XCTAssertTrue(store.isOverdue(overdue))
        XCTAssertFalse(store.isOverdue(today))
    }

    func testOverdueCountCountsOverdueRowsInTodayGroup() {
        let a = task("逾期 A", due: at(10))
        let b = task("逾期 B", due: at(12))
        let store = makeStore(tasks: [b, a])
        XCTAssertEqual(store.focusTask?.title, "逾期 A")
        XCTAssertEqual(store.todayTasks.map(\.title), ["逾期 B"])
        XCTAssertEqual(store.overdueCount, 1)
    }

    func testUpcomingCoversTomorrowThroughSeventhDay() {
        let tomorrow = task("明天", due: at(15))
        let seventh = task("第七天", due: at(21, 23))
        let eighth = task("第八天", due: at(22))
        let today = task("今天", due: at(14, 20))
        let store = makeStore(tasks: [eighth, seventh, tomorrow, today])
        XCTAssertEqual(store.upcomingTasks.map(\.title), ["明天", "第七天"])
    }

    func testRecentRecordsTakesLatestThree() {
        let store = makeStore(tasks: [], records: [
            record(at(1), title: "一"), record(at(10), title: "十"),
            record(at(5), title: "五"), record(at(13), title: "十三"),
        ])
        XCTAssertEqual(store.recentRecords.map(\.title), ["十三", "十", "五"])
    }

    func testPastWeeksExcludeCurrentAndFuture() {
        let store = makeStore(tasks: [
            task("上上周", due: at(31, month: 8), status: .completed),
            task("今天", due: at(14)),
            task("下周", due: at(22)),
        ])
        XCTAssertEqual(store.pastWeeks.map(\.week), [20])
    }

    func testCreateTaskReloadsOnSuccessAndReportsFailure() async {
        let repository = StubTimelineRepository()
        let store = TimelineStore()
        store.repository = repository

        let ok = await store.createTask(title: "买叶酸", dueAt: nil)
        XCTAssertTrue(ok)
        XCTAssertEqual(repository.createdTitles, ["买叶酸"])
        XCTAssertEqual(repository.fetchPlanCount, 1, "成功后要 reload")

        repository.shouldFail = true
        let failed = await store.createTask(title: "再来", dueAt: nil)
        XCTAssertFalse(failed)
        XCTAssertNotNil(store.errorMessage)
    }
}

private final class StubTimelineRepository: BusinessRepositoryProtocol, @unchecked Sendable {
    var createdTitles: [String] = []
    var fetchPlanCount = 0
    var shouldFail = false

    private let today = PregnancyDateCalculator.calendar.date(
        from: DateComponents(year: 2026, month: 9, day: 14, hour: 9))!

    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem {
        if shouldFail { throw APIError.invalidResponse }
        createdTitles.append(title)
        return TaskItem(id: UUID(), title: title, detail: description, status: .todo, version: 1,
                        dueAt: dueAt, scheduledFor: nil, assignedMemberID: assignedMemberID, changedByActor: .account)
    }

    func fetchToday() async throws -> TodaySnapshot {
        TodaySnapshot(pregnancyID: UUID(), asOf: today, weeks: 22, days: 6, priorityTask: nil, upcomingTasks: [], familyOpenTaskCount: 0)
    }
    func fetchPlan() async throws -> PlanSnapshot {
        fetchPlanCount += 1
        return PlanSnapshot(id: UUID(), pregnancyID: UUID(), version: 1, tasks: [])
    }
    func fetchFamily() async throws -> FamilySnapshot { FamilySnapshot(id: UUID(), name: "家", members: []) }
    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot { RecordSnapshot(records: []) }
    func createPregnancy(dueDate: Date) async throws -> UUID { throw APIError.notConfigured }
    func createRecord(draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func deleteRecord(recordID: UUID) async throws { throw APIError.notConfigured }
    func deleteTask(taskID: UUID) async throws { throw APIError.notConfigured }
    func fetchSafetyRules() async throws -> [SafetyRule] { [] }
    func fetchContentCollection(_ name: String) async throws -> ContentCollection {
        ContentCollection(id: name, source: "test", sourceURL: "", items: [])
    }
    func createTaskFromRecord(record: RecordItem, title: String, description: String?, dueAt: Date?) async throws -> TaskItem { throw APIError.notConfigured }
    func complete(task: TaskItem) async throws -> TaskItem { throw APIError.notConfigured }
    func delay(task: TaskItem, until: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func schedule(task: TaskItem, at: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem { throw APIError.notConfigured }
    func invite(phone: String, role: FamilyRole) async throws { throw APIError.notConfigured }
    func renameFamily(to name: String) async throws {}
    func updateMyMembership(nickname: String?, role: FamilyRole?) async throws {}
}
