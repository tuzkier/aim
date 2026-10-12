import XCTest
@testable import AimApp

final class PostpartumTests: XCTestCase {
    private let baby = UUID()
    private func record(kind: RecordType, start: Date, end: Date? = nil, volume: Double? = nil, diaper: String? = nil) -> RecordItem {
        let data = BabyCareRecordData(babyID: baby, mode: "unknown", volumeMl: volume, diaperKind: diaper, endedAt: end)
        let structured: RecordStructuredData
        switch kind { case .feeding: structured = .feeding(data); case .diaper: structured = .diaper(data); default: structured = .sleep(data) }
        return RecordItem(id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(), type: kind,
            occurredAt: start, visibility: .family, title: nil, content: nil, structuredData: structured,
            attachmentRefs: [], createdAt: start, updatedAt: start)
    }
    func testSleepIsClippedAtBeijingMidnightAndOverlapsAreNotCountedTwice() {
        let day = ISO8601DateFormatter().date(from: "2026-10-12T16:00:00Z")!
        let spans = [record(kind: .sleep, start: day.addingTimeInterval(-3600), end: day.addingTimeInterval(3600)),
                     record(kind: .sleep, start: day.addingTimeInterval(1800), end: day.addingTimeInterval(7200))]
        let summary = BabyDaySummary.calculate(records: spans, babyID: baby, now: day.addingTimeInterval(8000))
        XCTAssertEqual(summary.sleepSeconds, 7200)
    }
    func testUnknownAmountsRemainUnknownAndOnlyObservedVolumesAreSummed() {
        let now = Date.now
        let unknown = record(kind: .feeding, start: now)
        XCTAssertNil(BabyDaySummary.calculate(records: [unknown], babyID: baby, now: now).knownVolumeMl)
        let summary = BabyDaySummary.calculate(records: [unknown, record(kind: .feeding, start: now, volume: 60.5)], babyID: baby, now: now)
        XCTAssertEqual(summary.feedingCount, 2)
        XCTAssertEqual(summary.knownVolumeMl, 60.5)
        XCTAssertEqual(summary.unmeasuredFeeds, 1)
    }
    func testDiaperCountsAndBabyScopeDoNotMix() {
        let now = Date.now
        let records = [record(kind: .diaper, start: now, diaper: "both"), record(kind: .diaper, start: now, diaper: "dry")]
        let summary = BabyDaySummary.calculate(records: records, babyID: baby, now: now)
        XCTAssertEqual(summary.diaperCount, 2); XCTAssertEqual(summary.wetCount, 1); XCTAssertEqual(summary.dirtyCount, 1)
        XCTAssertEqual(BabyDaySummary.calculate(records: records, babyID: UUID(), now: now).diaperCount, 0)
    }
    func testCalendarMonthsDoNotUseThirtyDaysOrDriftAfterFebruary() {
        let date = ISO8601DateFormatter().date(from: "2026-01-31T00:00:00Z")!
        XCTAssertEqual(PostpartumCalendar.dateString(PostpartumCalendar.addingMonths(1, to: date)), "2026-02-28")
        XCTAssertEqual(PostpartumCalendar.dateString(PostpartumCalendar.addingMonths(2, to: date)), "2026-03-31")
    }
    func testBundleUsesTheCurrentDTPProgramAndIncludesFortyTwoDayCare() throws {
        let content = try XCTUnwrap(PostpartumContent.load())
        XCTAssertTrue(content.care.contains { $0.days == 42 })
        let ages = content.vaccines.filter { $0.id.hasPrefix("dtap") }.compactMap(\.months)
        XCTAssertEqual(ages, [2, 4, 6, 18, 72])
        XCTAssertTrue(content.vaccineSourceURL.contains("2073005020766703616"))
    }
    func testCareDTOUsesActualDateAndDoesNotSendAClientSleepDuration() throws {
        let now = Date.now
        let data = BabyCareRecordData(babyID: baby, endedAt: now, durationSeconds: 99999)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.aim.encode(APIRecordStructuredDataDTO(recordData: .sleep(data)))) as? [String: Any])
        XCTAssertNil(json["duration_seconds"])
        XCTAssertEqual(json["baby_id"] as? String, baby.uuidString.lowercased())
        XCTAssertNotNil(json["ended_at"])
    }
    func testCancelledTasksAreNotOpenAndBirthFreezesTheHomeLifecycle() {
        let task = TaskItem(id: UUID(), title: "孕期待办", detail: nil, status: .cancelled, version: 2,
            dueAt: .now, scheduledFor: nil, assignedMemberID: nil, changedByActor: .system)
        XCTAssertFalse(task.isOpen)
        let date = Date.now
        let pregnancy = PregnancySummary(id: UUID(), dueDate: date, weeks: 38, days: 0, status: "postpartum", birthDate: date)
        XCTAssertTrue(pregnancy.isPostpartum)
        XCTAssertEqual(pregnancy.postpartumDays(now: date), 0)
    }
}

@MainActor
final class PostpartumStoreTests: XCTestCase {
    func testFailedBirthDoesNotSwitchStageAndRetryUsesConfirmedServerState() async {
        let repository = PostpartumRepositoryStub()
        let store = PostpartumStore(repository: repository, pregnancy: repository.pregnancy)
        repository.failCreates = true
        let failed = await store.recordBirth(date: .now, babies: [])
        XCTAssertFalse(failed)
        XCTAssertFalse(store.pregnancy?.isPostpartum ?? true)
        XCTAssertNotNil(store.error)
        repository.failCreates = false
        let saved = await store.recordBirth(date: .now, babies: [])
        XCTAssertTrue(saved)
        XCTAssertTrue(store.pregnancy?.isPostpartum == true)
        XCTAssertNil(store.error)
    }
    func testAnOldLoadCannotReplaceTheNewlyConfirmedBirth() async {
        let repository = PostpartumRepositoryStub()
        repository.holdPregnancy = true
        let store = PostpartumStore(repository: repository, pregnancy: repository.pregnancy)
        let load = Task { await store.load() }
        for _ in 0..<200 where repository.heldPregnancy == nil { try? await Task.sleep(for: .milliseconds(5)) }
        let saved = await store.recordBirth(date: .now, babies: [])
        XCTAssertTrue(saved)
        repository.releasePregnancy()
        await load.value
        XCTAssertTrue(store.pregnancy?.isPostpartum == true)
        XCTAssertFalse(store.isLoading)
    }
}

@MainActor
private final class PostpartumRepositoryStub: BusinessRepositoryProtocol {
    var records: [RecordItem] = []
    var createdDrafts: [RecordDraft] = []
    private(set) var createdIDs: [UUID] = []
    var failCreates = false
    var failFetches = false
    /// 为真时 createRecord 挂起，直到 `release()`：模拟路上网络很慢。
    var holdCreates = false
    private var held: [CheckedContinuation<Void, Never>] = []
    var heldCount: Int { held.count }
    private(set) var deletedIDs: [UUID] = []
    let author = UUID()
    var pregnancy = PregnancySummary(id: UUID(), dueDate: .now, weeks: 38, days: 0)
    var holdPregnancy = false
    var heldPregnancy: CheckedContinuation<Void, Never>?
    func releasePregnancy() { heldPregnancy?.resume(); heldPregnancy = nil; holdPregnancy = false }
    func fetchPregnancy() async throws -> PregnancySummary? {
        let snapshot = pregnancy
        if holdPregnancy { await withCheckedContinuation { heldPregnancy = $0 } }
        return snapshot
    }
    func fetchBabies() async throws -> [BabyProfile] { [] }
    func recordBirth(date: Date, babies: [BabyDraft]) async throws -> BirthSnapshot {
        if failCreates { throw APIError.invalidResponse }
        pregnancy.status = "postpartum"; pregnancy.birthDate = date; pregnancy.birthRevision = UUID()
        return BirthSnapshot(pregnancy: pregnancy, babies: [])
    }

    var holdFetches = false
    private var fetchWaiters: [CheckedContinuation<Void, Never>] = []
    var heldFetchCount: Int { fetchWaiters.count }

    private func item(_ draft: RecordDraft) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: author,
            type: draft.type, occurredAt: draft.occurredAt, visibility: draft.visibility,
            title: draft.title, content: draft.content, structuredData: draft.structuredData,
            attachmentRefs: [], createdAt: .now, updatedAt: .now)
    }

    func release() {
        holdCreates = false
        held.forEach { $0.resume() }
        held = []
    }

    func releaseFetches() {
        holdFetches = false
        fetchWaiters.forEach { $0.resume() }
        fetchWaiters = []
    }
    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot {
        let snapshot = RecordSnapshot(records: records.filter { type == nil || $0.type == type })
        if holdFetches { await withCheckedContinuation { fetchWaiters.append($0) } }
        if failFetches { throw APIError.invalidResponse }
        return snapshot
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

    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem {
        if failCreates { throw APIError.invalidResponse }
        records.removeAll { $0.id == recordID }
        let created = item(draft)
        let value = RecordItem(id: recordID, pregnancyID: created.pregnancyID, familyID: created.familyID,
            authorAccountID: author, type: created.type, occurredAt: created.occurredAt, visibility: created.visibility,
            title: created.title, content: created.content, structuredData: created.structuredData,
            attachmentRefs: [], createdAt: created.createdAt, updatedAt: created.updatedAt)
        records.append(value)
        return value
    }
    func fetchSafetyRules() async throws -> [SafetyRule] { throw APIError.notConfigured }
    func fetchContentCollection(_ name: String) async throws -> ContentCollection { throw APIError.notConfigured }
    func fetchToday() async throws -> TodaySnapshot { throw APIError.notConfigured }
    func fetchPlan() async throws -> PlanSnapshot { PlanSnapshot(id: UUID(), pregnancyID: pregnancy.id, version: 1, tasks: []) }
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
