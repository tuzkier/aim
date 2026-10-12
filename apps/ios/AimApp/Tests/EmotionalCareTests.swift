import XCTest
@testable import AimApp

final class EmotionalCareTests: XCTestCase {
    private let low = [0, 0, 3, 0, 3, 3, 3, 3, 3, 3]
    private let high = [3, 3, 0, 3, 0, 0, 0, 0, 0, 0]

    func testBundledQuestionnairePreservesOriginalScoringAndAttribution() throws {
        let form = try EPDSQuestionnaire.load()
        XCTAssertEqual(form.result(low.map { Optional($0) }), EPDSResult(score: 0, item10: 0))
        XCTAssertEqual(form.result(high.map { Optional($0) }), EPDSResult(score: 30, item10: 3))
        XCTAssertTrue(form.attribution.contains("Cox"))
        XCTAssertTrue(form.attribution.contains("1987"))
        XCTAssertEqual(form.questions.map(\.id), Array(1...10))
    }

    func testIncompleteAnswersHaveNoTotalButItemTenStillShowsImmediateHelp() throws {
        let form = try EPDSQuestionnaire.load()
        var answers: [Int?] = Array(repeating: nil, count: 10)
        answers[9] = 2
        XCTAssertNil(form.result(answers))
        XCTAssertTrue(form.hasItem10Concern(answers))
        answers[9] = 3
        XCTAssertFalse(form.hasItem10Concern(answers))
        answers[0] = 4
        XCTAssertNil(form.result(answers))
    }

    func testLowTotalCannotOverrideItemTen() throws {
        var answers = low.map { Optional($0) }; answers[9] = 2
        let result = try XCTUnwrap(EPDSQuestionnaire.load().result(answers))
        XCTAssertEqual(result.score, 1)
        XCTAssertEqual(result.supportLevel, .immediate)
    }

    func testScreeningThresholdsDoNotProduceADiagnosis() {
        XCTAssertEqual(EPDSResult(score: 9, item10: 0).supportLevel, .support)
        XCTAssertEqual(EPDSResult(score: 10, item10: 0).supportLevel, .followUp)
        XCTAssertEqual(EPDSResult(score: 12, item10: 0).supportLevel, .followUp)
        XCTAssertEqual(EPDSResult(score: 13, item10: 0).supportLevel, .assessment)
    }

    func testHistoricalAndFutureAssessmentsDoNotDescribeThePresent() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(EmotionalSchedule.isHistoricalAssessment(now, now: now))
        XCTAssertFalse(EmotionalSchedule.isHistoricalAssessment(now.addingTimeInterval(-7 * 86_400), now: now))
        XCTAssertTrue(EmotionalSchedule.isHistoricalAssessment(now.addingTimeInterval(-7 * 86_400 - 1), now: now))
        XCTAssertTrue(EmotionalSchedule.isHistoricalAssessment(now.addingTimeInterval(1), now: now))
    }

    func testPregnancyAndPostpartumMilestoneBoundaries() {
        let birth = Date(timeIntervalSince1970: 1_800_000_000)
        func day(_ offset: Int) -> Date { EmotionalSchedule.calendar.date(byAdding: .day, value: offset, to: birth)! }
        XCTAssertEqual(EmotionalSchedule.period(weeks: 27, birthDate: nil, now: birth), .manual)
        XCTAssertEqual(EmotionalSchedule.period(weeks: 28, birthDate: nil, now: birth), .pregnancyLate)
        XCTAssertEqual(EmotionalSchedule.period(weeks: 40, birthDate: birth, now: day(13)), .manual)
        XCTAssertEqual(EmotionalSchedule.period(weeks: 40, birthDate: birth, now: day(14)), .postpartumTwoWeeks)
        XCTAssertEqual(EmotionalSchedule.period(weeks: nil, birthDate: birth, now: day(41)), .postpartumTwoWeeks)
        XCTAssertEqual(EmotionalSchedule.period(weeks: nil, birthDate: birth, now: day(42)), .postpartumSixWeeks)
        XCTAssertEqual(EmotionalSchedule.period(weeks: nil, birthDate: birth, now: day(366)), .manual)
    }

    func testEarlierOrOtherPeoplesAssessmentsCannotClearANewMilestone() {
        let account = UUID(), now = Date(timeIntervalSince1970: 1_800_000_000)
        let birth = EmotionalSchedule.calendar.date(byAdding: .day, value: -42, to: now)!
        func record(_ author: UUID, _ date: Date) -> RecordItem {
            RecordItem(id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: author,
                type: .epds, occurredAt: date, visibility: .private, title: nil, content: nil,
                structuredData: .epds(EPDSRecordData(version: EPDSQuestionnaire.supportedVersion, answers: low,
                    period: .postpartumTwoWeeks, score: 0, item10: 0, supportLevel: .support)),
                attachmentRefs: [], createdAt: date, updatedAt: date)
        }
        func needed(_ records: [RecordItem]) -> Bool {
            EmotionalSchedule.needsAssessment(records: records, accountID: account, weeks: nil,
                dueDate: nil, birthDate: birth, now: now)
        }
        XCTAssertTrue(needed([record(account, now.addingTimeInterval(-86_400))]))
        XCTAssertTrue(needed([record(UUID(), now)]))
        XCTAssertTrue(needed([record(account, now.addingTimeInterval(60))]))
        XCTAssertFalse(needed([record(account, now)]))
    }

    func testSharedEmotionalRecordIsStillEditableOnlyByItsAuthor() {
        let account = UUID()
        let record = RecordItem(id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: account,
            type: .mood, occurredAt: .now, visibility: .family, title: nil, content: nil,
            structuredData: .mood(MoodRecordData(mood: 2)), attachmentRefs: [], createdAt: .now, updatedAt: .now)
        XCTAssertTrue(record.isEditable(by: account))
        XCTAssertFalse(record.isEditable(by: UUID()))
    }

    func testRecordDTOUsesServerScoreAndSendsOnlyAnswersAndVersion() throws {
        let data = EPDSRecordData(version: EPDSQuestionnaire.supportedVersion, answers: low, period: .manual,
            score: 0, item10: 0, supportLevel: .support)
        let dto = APIRecordStructuredDataDTO(recordData: .epds(data))
        let encoded = try JSONEncoder().encode(dto)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(json["score"])
        XCTAssertNil(json["support_level"])
        XCTAssertEqual(json["answers"] as? [Int], low)
    }
}

@MainActor
final class EmotionalCareStoreTests: XCTestCase {
    private func mood(_ value: Int, now: Date = .now) -> RecordDraft {
        RecordDraft(type: .mood, occurredAt: now, visibility: .private, title: "心情", content: nil,
                    structuredData: .mood(MoodRecordData(mood: value)))
    }
    func testFailedSaveHasAnErrorAndCanBeRetriedWithTheSameDraft() async {
        let repository = EmotionalRepositoryStub()
        let store = EmotionalCareStore(repository: repository, accountID: repository.author)
        repository.failCreates = true
        let failed = await store.save(mood(2))
        XCTAssertFalse(failed)
        XCTAssertNotNil(store.error)
        XCTAssertTrue(store.records.isEmpty)
        repository.failCreates = false
        let saved = await store.save(mood(2))
        XCTAssertTrue(saved)
        XCTAssertNil(store.error)
        XCTAssertEqual(store.records.first?.visibility, .private)
        XCTAssertEqual(repository.createdDrafts.count, 1)
    }
    func testAnOlderFetchCannotEraseANewlySavedMood() async {
        let repository = EmotionalRepositoryStub()
        repository.holdFetches = true
        let store = EmotionalCareStore(repository: repository, accountID: repository.author)
        let loading = Task { await store.load() }
        for _ in 0..<200 where repository.heldFetchCount < 2 { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(repository.heldFetchCount, 2)
        let saved = await store.save(mood(5))
        XCTAssertTrue(saved)
        repository.releaseFetches()
        await loading.value
        XCTAssertEqual(store.records.count, 1)
        XCTAssertFalse(store.isLoading)
        XCTAssertEqual(store.todayMood()?.displaySummary, "很开心")
    }
    func testSharedRecordsFromAnotherAuthorCannotBeEditedOrDeleted() async {
        let repository = EmotionalRepositoryStub()
        let own = try! await repository.createRecord(draft: mood(3))
        let otherStore = EmotionalCareStore(repository: repository, accountID: UUID())
        await otherStore.load()
        XCTAssertTrue(otherStore.records.isEmpty)
        let edited = await otherStore.save(mood(1), editing: own)
        let deleted = await otherStore.delete(own)
        XCTAssertFalse(edited)
        XCTAssertFalse(deleted)
        XCTAssertTrue(repository.deletedIDs.isEmpty)
    }
    func testTodayMoodUsesBeijingDayAndEditingDoesNotCreateADuplicate() async throws {
        let repository = EmotionalRepositoryStub()
        let now = ISO8601DateFormatter().date(from: "2026-10-12T16:30:00Z")!
        _ = try await repository.createRecord(draft: mood(2, now: now.addingTimeInterval(-3600)))
        let current = try await repository.createRecord(draft: mood(4, now: now))
        let store = EmotionalCareStore(repository: repository, accountID: repository.author)
        await store.load()
        XCTAssertEqual(store.todayMood(now: now)?.id, current.id)
        let updated = await store.save(mood(5, now: now), editing: current)
        XCTAssertTrue(updated)
        XCTAssertEqual(store.records.count, 2)
        XCTAssertEqual(store.todayMood(now: now)?.displaySummary, "很开心")
    }
}

@MainActor
private final class EmotionalRepositoryStub: BusinessRepositoryProtocol {
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
