import XCTest
@testable import AimApp

@MainActor
final class FetalMovementStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let accountA = UUID(), pregnancyA = UUID()
    private let accountB = UUID(), pregnancyB = UUID()

    override func setUp() {
        super.setUp()
        suiteName = "FetalMovementStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore(
        repository: FakeFetalRepository = FakeFetalRepository(), dedupe: TimeInterval = 3, bound: Bool = true
    ) -> FetalMovementStore {
        let store = FetalMovementStore(defaults: defaults, dedupeInterval: dedupe)
        store.repository = repository
        store.clock = { [unowned self] in self.now }
        if bound { store.bind(accountID: accountA, pregnancyID: pregnancyA) }
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
        XCTAssertTrue(store.unsaved.isEmpty)
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
        XCTAssertEqual(store.unsaved.count, 1)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(makeStore(repository: repository).unsaved.count, 1, "没保存上的结果不能丢")

        repository.failCreates = false
        let saved = await store.saveUnsaved()
        XCTAssertTrue(saved)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(makeStore(repository: repository).unsaved.isEmpty)
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

    /// 上一次没保存上、这一次也没保存上：两条都要留着，不能后一条把前一条覆盖掉。
    func testTwoFailedSavesAreBothQueuedAndRetriedInOrder() async {
        let repository = FakeFetalRepository()
        repository.failCreates = true
        let store = makeStore(repository: repository)
        store.start(); now += 30; _ = store.tap()
        let first = await store.finish()
        now += 3_600
        store.start(); now += 30; _ = store.tap()
        let second = await store.finish()

        XCTAssertEqual(first?.saved, false)
        XCTAssertEqual(second?.saved, false)
        XCTAssertEqual(store.unsaved.count, 2)
        XCTAssertEqual(makeStore(repository: repository).unsaved.count, 2, "重启后队列还在")

        repository.failCreates = false
        let saved = await store.saveUnsaved()

        XCTAssertTrue(saved)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertEqual(repository.createdDrafts.map(\.occurredAt),
                       [first?.result.startedAt, second?.result.startedAt].compactMap { $0 },
                       "旧的先保存")
        XCTAssertTrue(makeStore(repository: repository).unsaved.isEmpty, "重启后也为空")
    }

    /// 换账号或家庭后各自独立；切回来还能接着数。
    func testEachAccountAndPregnancyKeepsItsOwnCount() {
        let store = makeStore()
        store.start()
        now += 40
        _ = store.tap()

        store.bind(accountID: accountB, pregnancyID: pregnancyB)
        XCTAssertNil(store.active)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertTrue(store.sessions.isEmpty)

        store.bind(accountID: accountA, pregnancyID: pregnancyA)
        XCTAssertEqual(store.active?.count, 1)
    }

    /// 不知道是哪一家时，什么都不能记，免得存错地方。
    func testNothingHappensBeforeBinding() async {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository, bound: false)

        store.start()
        XCTAssertNil(store.active)
        XCTAssertEqual(store.tap(), .ignored)
        let completion = await store.finish()
        XCTAssertNil(completion)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertTrue(repository.createdDrafts.isEmpty)
    }

    /// 保存还没回来时再点「重试」，不能把同一条存两遍。
    func testSavingAgainWhileASaveIsInFlightDoesNothing() async {
        let repository = FakeFetalRepository()
        let gate = CreateGate()
        repository.gate = gate
        let store = makeStore(repository: repository)
        store.start()
        now += 30
        _ = store.tap()

        let finishing = Task { await store.finish() }
        while await gate.calls == 0 { await Task.yield() }

        // 第二次调用放进独立任务：缺了防重入时它会卡在同一道闸门上，放行后多发一次请求，
        // 测试以失败而不是挂起的方式暴露问题。
        let retrying = Task { await store.saveUnsaved() }
        for _ in 0..<10 { await Task.yield() }

        await gate.release()
        let second = await retrying.value
        let completion = await finishing.value
        XCTAssertFalse(second, "保存进行中，第二次调用直接返回")

        XCTAssertEqual(completion?.saved, true)
        let calls = await gate.calls
        XCTAssertEqual(calls, 1, "只发出一次保存请求")
        XCTAssertEqual(repository.createdDrafts.count, 1)
        XCTAssertTrue(store.unsaved.isEmpty)
    }

    /// 打开计数页就直接开始数、历史还没拉回来时，「和平时比」不能静默缺失。
    func testBaselineIsAvailableEvenIfHistoryWasNotLoaded() async {
        let repository = FakeFetalRepository()
        for seconds in [600, 620, 640] { repository.seed(seconds: seconds, at: now - 86_400) }
        let store = makeStore(repository: repository, dedupe: 0)
        store.start()
        for _ in 1...10 { now += 200; _ = store.tap() }

        let completion = await store.finish()

        XCTAssertEqual(completion?.baselineSeconds, 620)
        XCTAssertEqual(completion?.isSlow, true)
    }
}

/// 让 createRecord 停在半路，直到测试放行；同时数一共被调了几次。
private actor CreateGate {
    private(set) var calls = 0
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        calls += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// 只实现胎动用到的三个接口；其余照抄 LibraryStoreTests 的 FakeLibraryRepository，
/// 一律 `throw APIError.notConfigured`（有默认实现的不必写）。
private final class FakeFetalRepository: BusinessRepositoryProtocol, @unchecked Sendable {
    var records: [RecordItem] = []
    var createdDrafts: [RecordDraft] = []
    var failCreates = false
    var gate: CreateGate?

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
        if let gate { await gate.pass() }
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
