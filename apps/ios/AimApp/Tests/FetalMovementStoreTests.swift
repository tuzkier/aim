import XCTest
@testable import AimApp

@MainActor
final class FetalMovementStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "FetalMovementStoreTests-\(UUID().uuidString)")
    }

    private func makeStore(repository: FakeFetalRepository = FakeFetalRepository(), dedupe: TimeInterval = 3) -> FetalMovementStore {
        let store = FetalMovementStore(defaults: defaults, dedupeInterval: dedupe)
        store.repository = repository
        store.clock = { [unowned self] in self.now }
        return store
    }

    func testAnActiveCountSurvivesARelaunch() {
        let first = makeStore()
        first.start()
        now += 40
        _ = first.tap()

        let relaunched = makeStore()
        XCTAssertEqual(relaunched.active?.count, 1, "App 被系统杀掉后要从断点继续")
        XCTAssertEqual(relaunched.active?.startedAt, first.active?.startedAt)
    }

    func testFinishingSavesTheRecordAndReloads() async {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository, dedupe: 0)
        store.start()
        for _ in 1...10 { now += 60; _ = store.tap() }

        let completion = await store.finish()

        XCTAssertEqual(completion?.result.outcome, .reached)
        XCTAssertEqual(completion?.saved, true)
        XCTAssertNil(store.active)
        XCTAssertNil(store.unsaved)
        XCTAssertEqual(repository.createdDrafts.first?.type, .fetalMovement)
        XCTAssertEqual(store.sessions.count, 1, "保存后重新拉取档案")
    }

    func testAFailedSaveKeepsTheResultForRetryAcrossRelaunch() async {
        let repository = FakeFetalRepository()
        repository.failCreates = true
        let store = makeStore(repository: repository)
        store.start()
        now += 30
        _ = store.tap()

        let completion = await store.finish()

        XCTAssertEqual(completion?.saved, false)
        XCTAssertNotNil(store.unsaved)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNotNil(makeStore(repository: repository).unsaved, "没保存上的结果不能丢")

        repository.failCreates = false
        let saved = await store.saveUnsaved()
        XCTAssertTrue(saved)
        XCTAssertNil(store.unsaved)
        XCTAssertNil(makeStore(repository: repository).unsaved)
    }

    func testBaselineIsCapturedBeforeTheNewSessionIsSaved() async {
        let repository = FakeFetalRepository()
        for seconds in [600, 620, 640] { repository.seed(seconds: seconds, at: now - 86_400) }
        let store = makeStore(repository: repository, dedupe: 0)
        await store.load()
        store.start()
        for _ in 1...10 { now += 200; _ = store.tap() }

        let completion = await store.finish()

        XCTAssertEqual(completion?.baselineSeconds, 620)
        XCTAssertEqual(completion?.isSlow, true, "2000 秒 > 620 × 2 且 > 30 分钟")
    }

    func testDiscardingAnEmptyCountLeavesNothingBehind() {
        let store = makeStore()
        store.start()
        store.discardActive()
        XCTAssertNil(store.active)
        XCTAssertNil(makeStore().active)
    }
}

/// 只实现胎动用到的三个接口；其余照抄 LibraryStoreTests 的 FakeLibraryRepository，
/// 一律 `throw APIError.notConfigured`（有默认实现的不必写）。
private final class FakeFetalRepository: BusinessRepositoryProtocol, @unchecked Sendable {
    var records: [RecordItem] = []
    var createdDrafts: [RecordDraft] = []
    var failCreates = false

    func seed(seconds: Int, at date: Date) {
        records.append(item(FetalMovementResult(
            startedAt: date, durationSeconds: seconds, count: 10, outcome: .reached,
            taps: Array(repeating: 0, count: 10)).draft))
    }

    private func item(_ draft: RecordDraft) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: draft.type, occurredAt: draft.occurredAt, visibility: draft.visibility,
            title: draft.title, content: draft.content, structuredData: draft.structuredData,
            attachmentRefs: [], createdAt: .now, updatedAt: .now)
    }

    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot {
        RecordSnapshot(records: records.filter { type == nil || $0.type == type })
    }

    func createRecord(draft: RecordDraft) async throws -> RecordItem {
        if failCreates { throw APIError.invalidResponse }
        createdDrafts.append(draft)
        let created = item(draft)
        records.append(created)
        return created
    }

    func deleteRecord(recordID: UUID) async throws { records.removeAll { $0.id == recordID } }

    // 以下照抄 Tests/LibraryStoreTests.swift 里 FakeLibraryRepository 的其余必需方法，
    // 全部 throw APIError.notConfigured（返回 Void 的写成空实现）。
    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func fetchSafetyRules() async throws -> [SafetyRule] { throw APIError.notConfigured }
    func fetchContentCollection(_ name: String) async throws -> ContentCollection { throw APIError.notConfigured }
    func fetchToday() async throws -> TodaySnapshot { throw APIError.notConfigured }
    func fetchPlan() async throws -> PlanSnapshot { throw APIError.notConfigured }
    func fetchFamily() async throws -> FamilySnapshot { throw APIError.notConfigured }
    func createPregnancy(dueDate: Date) async throws -> UUID { throw APIError.notConfigured }
    func deleteTask(taskID: UUID) async throws {}
    func createTaskFromRecord(record: RecordItem, title: String, description: String?, dueAt: Date?) async throws -> TaskItem { throw APIError.notConfigured }
    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem { throw APIError.notConfigured }
    func complete(task: TaskItem) async throws -> TaskItem { throw APIError.notConfigured }
    func delay(task: TaskItem, until: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func schedule(task: TaskItem, at: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem { throw APIError.notConfigured }
    func invite(phone: String, role: FamilyRole) async throws { throw APIError.notConfigured }
    func renameFamily(to name: String) async throws {}
    func updateMyMembership(nickname: String?, role: FamilyRole?) async throws {}
    func requestAccountDeletion(password: String) async throws { throw APIError.notConfigured }
}
