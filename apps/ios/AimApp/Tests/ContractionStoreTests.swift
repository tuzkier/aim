import XCTest
@testable import AimApp

@MainActor
final class ContractionStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let account = UUID(), pregnancy = UUID()

    override func setUp() {
        super.setUp()
        suiteName = "ContractionStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore(repository: BusinessRepositoryProtocol? = nil) -> ContractionStore {
        let store = ContractionStore(defaults: defaults, notificationCenter: NotificationCenter())
        store.clock = { [unowned self] in self.now }
        store.repository = repository
        store.bind(accountID: account, pregnancyID: pregnancy)
        return store
    }

    private func contract(_ store: ContractionStore, seconds: TimeInterval = 60, then rest: TimeInterval = 240) {
        store.toggle(); now += seconds
        store.toggle(); now += rest
    }

    func testUnboundStoreIgnoresToggles() {
        let store = ContractionStore(defaults: defaults, notificationCenter: NotificationCenter())
        XCTAssertEqual(store.toggle(), .ignored)
        XCTAssertNil(store.active)
    }

    func testActiveTimerIsRestoredForTheSameScopeOnly() {
        let first = makeStore()
        contract(first)
        let again = makeStore()
        XCTAssertEqual(again.active, first.active, "同一账号与孕期能接着计时")

        let other = ContractionStore(defaults: defaults, notificationCenter: NotificationCenter())
        other.bind(accountID: UUID(), pregnancyID: pregnancy)
        XCTAssertNil(other.active, "换了账号看不到别人的计时")
    }

    func testFinishSavesAndReturnsTheNewRecordID() async {
        let repository = FakeContractionRepository()
        let store = makeStore(repository: repository)
        contract(store); contract(store)
        let outcome = await store.finish()
        XCTAssertEqual(outcome?.result.entries.count, 2)
        XCTAssertNotNil(outcome?.savedRecordID)
        XCTAssertEqual(outcome?.savedRecordID, repository.createdIDs.first)
        XCTAssertNil(store.active)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertEqual(repository.createdDrafts.first?.type, .contraction)
        XCTAssertEqual(store.latest?.id, repository.createdIDs.first, "保存后重新拉取历史")
    }

    func testFinishWithoutACompletedContractionDoesNothing() async {
        let store = makeStore()
        store.toggle()
        let outcome = await store.finish()
        XCTAssertNil(outcome)
        XCTAssertNotNil(store.active, "宫缩还在进行中，不能把计时丢掉")
    }

    func testFinishDropsTheRunningContractionButKeepsCompletedOnes() async {
        let store = makeStore(repository: FakeContractionRepository())
        contract(store)
        store.toggle()  // 第二次开始了但没结束
        let outcome = await store.finish()
        XCTAssertEqual(outcome?.result.entries.count, 1)
    }

    func testFinishKeepsOnlyWhatTheServerAccepts() async {
        let repository = FakeContractionRepository()
        let store = makeStore(repository: repository)
        for _ in 0..<501 { contract(store, seconds: 30, then: 30) }
        let outcome = await store.finish()
        XCTAssertEqual(outcome?.result.entries.count, 500)
        XCTAssertEqual(outcome?.result.entries.first?.start, 0)
        XCTAssertNotNil(outcome?.savedRecordID)
    }

    func testFailedSaveIsKeptLocallyAndRetried() async {
        let repository = FakeContractionRepository()
        repository.failCreates = true
        let store = makeStore(repository: repository)
        contract(store)
        let outcome = await store.finish()
        XCTAssertNil(outcome?.savedRecordID)
        XCTAssertEqual(store.unsaved.count, 1)
        XCTAssertEqual(store.saveError, "没保存上，重试")

        // 重新绑定（模拟重启）后队列还在。
        XCTAssertEqual(makeStore().unsaved.count, 1)

        repository.failCreates = false
        let saved = await store.saveUnsaved()
        XCTAssertTrue(saved)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertEqual(repository.createdDrafts.count, 1)
        XCTAssertNil(store.saveError)
        XCTAssertTrue(makeStore().unsaved.isEmpty, "保存成功后本地队列也清掉")
    }

    func testFailedHistoryLoadIsNotReportedAsAFailedSave() async {
        let repository = FakeContractionRepository()
        repository.failFetches = true
        let store = makeStore(repository: repository)
        await store.load()
        XCTAssertNotNil(store.loadError)
        XCTAssertNil(store.saveError, "拉历史失败不能显示成「没保存上，重试」")

        repository.failFetches = false
        await store.load()
        XCTAssertNil(store.loadError, "历史加载成功后清掉")
    }

    func testSaveErrorIsClearedOnceTheQueueIsEmpty() async {
        let repository = FakeContractionRepository()
        repository.failCreates = true
        let store = makeStore(repository: repository)
        contract(store)
        _ = await store.finish()
        XCTAssertEqual(store.saveError, "没保存上，重试")
        XCTAssertNil(store.loadError)

        repository.failCreates = false
        repository.failFetches = true  // 保存成功、随后拉历史失败
        _ = await store.saveUnsaved()
        XCTAssertNil(store.saveError)
        XCTAssertNotNil(store.loadError)
    }

    func testFinishWithTimeoutReturnsTheSavedRecordWhenFast() async {
        let repository = FakeContractionRepository()
        let store = makeStore(repository: repository)
        contract(store)
        let outcome = await store.finish(timeout: .seconds(5))
        XCTAssertEqual(outcome?.timedOut, false)
        XCTAssertEqual(outcome?.savedRecordID, repository.createdIDs.first)
    }

    func testFinishWithTimeoutGivesUpWaitingButKeepsSaving() async throws {
        let repository = FakeContractionRepository()
        repository.holdCreates = true
        let store = makeStore(repository: repository)
        contract(store)

        let outcome = await store.finish(timeout: .milliseconds(100))
        XCTAssertEqual(outcome?.timedOut, true)
        XCTAssertNil(outcome?.savedRecordID, "超时就不带关联")
        XCTAssertEqual(outcome?.result.entries.count, 1)
        XCTAssertNil(store.active)
        XCTAssertEqual(store.unsaved.count, 1, "保存还在进行，计时留在队列里")

        // 保存没被取消：放行后照常存上、清空队列。
        repository.release()
        for _ in 0..<200 where !store.unsaved.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertEqual(repository.createdDrafts.count, 1)
        XCTAssertTrue(makeStore().unsaved.isEmpty, "落盘的队列也清掉")
        XCTAssertNil(store.saveError)
    }

    func testStatusUsesGestationalWeeks() {
        let store = makeStore()
        store.gestationalWeeks = 34
        for _ in 0..<4 { contract(store, seconds: 40, then: 260) }
        now -= 260  // 停在第 4 次刚结束
        XCTAssertEqual(store.status?.stage, .pretermAlert)
        store.gestationalWeeks = 38
        XCTAssertNotEqual(store.status?.stage, .pretermAlert)
    }

    func testStaleTimerNeedsADecision() {
        let store = makeStore()
        contract(store, then: 0)
        XCTAssertFalse(store.needsStaleDecision)
        now += 21_601
        XCTAssertTrue(store.needsStaleDecision)
        store.discardActive()
        XCTAssertFalse(store.needsStaleDecision)
        XCTAssertNil(store.active)
    }

    func testResumeAfterLaunchCapsALongRunningContraction() {
        let store = makeStore()
        store.toggle()
        now += 3600
        store.resumeAfterLaunch()
        XCTAssertEqual(store.active?.isContracting, false)
        XCTAssertEqual(store.active?.entries().first?.duration, 600)
    }

    func testRemoveLastPersists() {
        let store = makeStore()
        contract(store)
        store.removeLast()
        XCTAssertEqual(makeStore().active?.spans.isEmpty ?? true, true)
    }
}

/// 只实现宫缩计时用到的三个接口，写法照 FetalMovementStoreTests 的 FakeFetalRepository；
/// 其余一律 `throw APIError.notConfigured`（返回 Void 的写成空实现）。
private final class FakeContractionRepository: BusinessRepositoryProtocol, @unchecked Sendable {
    var records: [RecordItem] = []
    var createdDrafts: [RecordDraft] = []
    private(set) var createdIDs: [UUID] = []
    var failCreates = false
    var failFetches = false
    /// 为真时 createRecord 挂起，直到 `release()`：模拟路上网络很慢。
    var holdCreates = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private(set) var deletedIDs: [UUID] = []

    private func item(_ draft: RecordDraft) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: draft.type, occurredAt: draft.occurredAt, visibility: draft.visibility,
            title: draft.title, content: draft.content, structuredData: draft.structuredData,
            attachmentRefs: [], createdAt: .now, updatedAt: .now)
    }

    func release() {
        holdCreates = false
        held.forEach { $0.resume() }
        held = []
    }

    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot {
        if failFetches { throw APIError.invalidResponse }
        return RecordSnapshot(records: records.filter { type == nil || $0.type == type })
    }

    func createRecord(draft: RecordDraft) async throws -> RecordItem {
        if holdCreates { await withCheckedContinuation { held.append($0) } }
        if failCreates { throw APIError.invalidResponse }
        createdDrafts.append(draft)
        let created = item(draft)
        createdIDs.append(created.id)
        records.append(created)
        return created
    }

    func deleteRecord(recordID: UUID) async throws {
        deletedIDs.append(recordID)
        records.removeAll { $0.id == recordID }
    }

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
