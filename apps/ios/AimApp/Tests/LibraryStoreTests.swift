import XCTest
@testable import AimApp

@MainActor
final class LibraryStoreTests: XCTestCase {
    private func makeStore(records: [RecordItem] = []) -> (LibraryStore, FakeLibraryRepository) {
        let repository = FakeLibraryRepository(records: records)
        let store = LibraryStore()
        store.repository = repository
        store.snapshot = LibrarySnapshot(
            records: records,
            safetyRuleCount: 0,
            collectionSizes: ["preparation": 7]
        )
        return (store, repository)
    }

    private func checklistRecord(_ itemID: String, done: Bool) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .checklist, occurredAt: .now, visibility: .family,
            title: nil, content: nil,
            structuredData: .checklist(
                ChecklistRecordData(collection: "preparation", itemID: itemID, done: done)),
            attachmentRefs: [], createdAt: .now, updatedAt: .now
        )
    }

    func testAddingAQuestionCreatesAnUnansweredRecord() async {
        let (store, repository) = makeStore()

        await store.addQuestion("能不能继续游泳？")

        XCTAssertEqual(repository.createdDrafts.count, 1)
        let draft = repository.createdDrafts[0]
        XCTAssertEqual(draft.type, .question)
        XCTAssertEqual(draft.content, "能不能继续游泳？")
        guard case let .question(data) = draft.structuredData else {
            return XCTFail("应当是 question 结构")
        }
        XCTAssertFalse(data.answered)
    }

    func testBlankQuestionsAreRejectedBeforeHittingTheNetwork() async {
        let (store, repository) = makeStore()

        await store.addQuestion("   ")

        XCTAssertTrue(repository.createdDrafts.isEmpty)
    }

    /// 第一次勾选没有已存记录，要新建。
    func testCheckingAnItemForTheFirstTimeCreatesARecord() async {
        let (store, repository) = makeStore()

        await store.toggleChecklistItem(collection: "preparation", itemID: "documents")

        XCTAssertEqual(repository.createdDrafts.count, 1)
        guard case let .checklist(data) = repository.createdDrafts[0].structuredData else {
            return XCTFail("应当是 checklist 结构")
        }
        XCTAssertEqual(data.itemID, "documents")
        XCTAssertTrue(data.done)
        XCTAssertTrue(repository.updatedRecordIDs.isEmpty, "第一次勾选不该走更新")
    }

    /// 再次点击是取消勾选——必须更新那条已存记录，而不是再建一条。
    /// 否则同一个条目会攒出一堆记录，进度算出来永远是错的。
    func testUncheckingUpdatesTheExistingRecordRatherThanCreatingAnother() async {
        let existing = checklistRecord("documents", done: true)
        let (store, repository) = makeStore(records: [existing])

        await store.toggleChecklistItem(collection: "preparation", itemID: "documents")

        XCTAssertTrue(repository.createdDrafts.isEmpty, "已有记录时不该新建")
        XCTAssertEqual(repository.updatedRecordIDs, [existing.id])
        guard case let .checklist(data) = repository.updatedDrafts[0].structuredData else {
            return XCTFail("应当是 checklist 结构")
        }
        XCTAssertFalse(data.done)
    }

    /// 另一个集合的同名条目不能被误认成同一条。
    func testItemsAreScopedToTheirCollection() async {
        let other = RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .checklist, occurredAt: .now, visibility: .family,
            title: nil, content: nil,
            structuredData: .checklist(
                ChecklistRecordData(collection: "hangzhou", itemID: "documents", done: true)),
            attachmentRefs: [], createdAt: .now, updatedAt: .now
        )
        let (store, repository) = makeStore(records: [other])

        await store.toggleChecklistItem(collection: "preparation", itemID: "documents")

        XCTAssertEqual(repository.createdDrafts.count, 1, "不同集合的同名条目应各自独立")
        XCTAssertTrue(repository.updatedRecordIDs.isEmpty)
    }

    func testMarkingAQuestionAnsweredKeepsItsText() async {
        let question = RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .question, occurredAt: .now, visibility: .family,
            title: nil, content: "能不能继续游泳？",
            structuredData: .question(QuestionRecordData(answered: false, answer: nil)),
            attachmentRefs: [], createdAt: .now, updatedAt: .now
        )
        let (store, repository) = makeStore(records: [question])

        await store.markQuestionAnswered(question, answer: "可以，注意水温")

        XCTAssertEqual(repository.updatedRecordIDs, [question.id])
        let draft = repository.updatedDrafts[0]
        XCTAssertEqual(draft.content, "能不能继续游泳？")
        guard case let .question(data) = draft.structuredData else {
            return XCTFail("应当是 question 结构")
        }
        XCTAssertTrue(data.answered)
        XCTAssertEqual(data.answer, "可以，注意水温")
    }
}

private final class FakeLibraryRepository: BusinessRepositoryProtocol, @unchecked Sendable {
    var records: [RecordItem]
    var createdDrafts: [RecordDraft] = []
    var updatedDrafts: [RecordDraft] = []
    var updatedRecordIDs: [UUID] = []

    init(records: [RecordItem]) { self.records = records }

    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot {
        RecordSnapshot(records: records)
    }

    func createRecord(draft: RecordDraft) async throws -> RecordItem {
        createdDrafts.append(draft)
        return RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: draft.type, occurredAt: draft.occurredAt, visibility: draft.visibility,
            title: draft.title, content: draft.content, structuredData: draft.structuredData,
            attachmentRefs: [], createdAt: .now, updatedAt: .now
        )
    }

    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem {
        updatedRecordIDs.append(recordID)
        updatedDrafts.append(draft)
        return RecordItem(
            id: recordID, pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: draft.type, occurredAt: draft.occurredAt, visibility: draft.visibility,
            title: draft.title, content: draft.content, structuredData: draft.structuredData,
            attachmentRefs: [], createdAt: .now, updatedAt: .now
        )
    }

    func fetchSafetyRules() async throws -> [SafetyRule] { [] }
    func fetchContentCollection(_ name: String) async throws -> ContentCollection {
        ContentCollection(id: name, source: "test", sourceURL: "", items: [])
    }
    func fetchToday() async throws -> TodaySnapshot { throw APIError.notConfigured }
    func fetchPlan() async throws -> PlanSnapshot { throw APIError.notConfigured }
    func fetchFamily() async throws -> FamilySnapshot { throw APIError.notConfigured }
    func createPregnancy(dueDate: Date) async throws -> UUID { throw APIError.notConfigured }
    func deleteRecord(recordID: UUID) async throws {}
    func deleteTask(taskID: UUID) async throws {}
    func createTaskFromRecord(record: RecordItem, title: String, description: String?, dueAt: Date?) async throws -> TaskItem { throw APIError.notConfigured }
    func complete(task: TaskItem) async throws -> TaskItem { throw APIError.notConfigured }
    func delay(task: TaskItem, until: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func schedule(task: TaskItem, at: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem { throw APIError.notConfigured }
    func invite(phone: String, role: FamilyRole) async throws { throw APIError.notConfigured }
}
