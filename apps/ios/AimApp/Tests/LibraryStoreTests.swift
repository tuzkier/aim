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
}

@MainActor
final class LibraryStoreReloadTests: XCTestCase {
    /// 资料库原本只在首次加载，之后用户在时间线新记的产检这里看不到。
    func testLoadingAgainPicksUpNewRecords() async {
        let repository = CountingRepository()
        let store = LibraryStore()
        store.repository = repository

        await store.load()
        XCTAssertEqual(store.snapshot.records.count, 0)

        repository.records = [CountingRepository.makeCheckup()]
        await store.load()

        XCTAssertEqual(store.snapshot.records.count, 1)
        XCTAssertEqual(repository.fetchCount, 2)
    }
}

private final class CountingRepository: BusinessRepositoryProtocol, @unchecked Sendable {
    var records: [RecordItem] = []
    var fetchCount = 0

    static func makeCheckup() -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .checkup, occurredAt: .now, visibility: .family, title: nil, content: nil,
            structuredData: .checkup(CheckupRecordData(
                hospital: "市一医院", examItems: "常规", result: "正常", doctorAdvice: "复查")),
            attachmentRefs: [], createdAt: .now, updatedAt: .now
        )
    }

    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot {
        fetchCount += 1
        return RecordSnapshot(records: records)
    }
    func fetchSafetyRules() async throws -> [SafetyRule] { [] }
    func fetchContentCollection(_ name: String) async throws -> ContentCollection {
        ContentCollection(id: name, source: "test", sourceURL: "", items: [])
    }
    func fetchToday() async throws -> TodaySnapshot { throw APIError.notConfigured }
    func fetchPlan() async throws -> PlanSnapshot { throw APIError.notConfigured }
    func fetchFamily() async throws -> FamilySnapshot { throw APIError.notConfigured }
    func createPregnancy(dueDate: Date) async throws -> UUID { throw APIError.notConfigured }
    func createRecord(draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func deleteRecord(recordID: UUID) async throws {}
    func deleteTask(taskID: UUID) async throws {}
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
}

@MainActor
final class LibraryEntryActionTests: XCTestCase {
    private func entryRecord(_ title: String) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .knowledge, occurredAt: .now, visibility: .family,
            title: title, content: nil,
            structuredData: .knowledge(KnowledgeRecordData(
                category: "nutrition", form: .tip, body: "正文")),
            attachmentRefs: [], createdAt: .now, updatedAt: .now)
    }

    /// 资料库不该只能看。存错了、过时了，要能删掉。
    func testAnEntryCanBeDeleted() async {
        let record = entryRecord("过时的菜谱")
        let repository = DeletingRepository()
        let store = LibraryStore()
        store.repository = repository
        store.snapshot = LibrarySnapshot(records: [record])

        await store.deleteEntry(id: record.id)

        XCTAssertEqual(repository.deletedRecordIDs, [record.id])
    }

    /// 在某个分类里问 AIM，要带上这个分类的上下文，
    /// 否则模型不知道该往哪里存。
    func testAskingFromACategoryCarriesItsContext() {
        let snapshot = LibrarySnapshot(records: [entryRecord("菠菜猪肝汤")])

        let context = LibraryCategoryID.nutrition.askContext(from: snapshot)

        XCTAssertTrue(context.summary.contains("吃什么"))
        XCTAssertTrue(context.summary.contains("菠菜猪肝汤"))
    }

    /// 针对某一条提问时，上下文要带上这条本身。
    func testAskingAboutAnEntryCarriesTheEntry() {
        let entry = KnowledgeEntry(record: entryRecord("菠菜猪肝汤"))!

        let context = entry.askContext

        XCTAssertTrue(context.summary.contains("菠菜猪肝汤"))
    }
}

private final class DeletingRepository: BusinessRepositoryProtocol, @unchecked Sendable {
    var deletedRecordIDs: [UUID] = []
    func deleteRecord(recordID: UUID) async throws { deletedRecordIDs.append(recordID) }
    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot { RecordSnapshot(records: []) }
    func fetchSafetyRules() async throws -> [SafetyRule] { [] }
    func fetchContentCollection(_ name: String) async throws -> ContentCollection {
        ContentCollection(id: name, source: "test", sourceURL: "", items: [])
    }
    func fetchToday() async throws -> TodaySnapshot { throw APIError.notConfigured }
    func fetchPlan() async throws -> PlanSnapshot { throw APIError.notConfigured }
    func fetchFamily() async throws -> FamilySnapshot { throw APIError.notConfigured }
    func createPregnancy(dueDate: Date) async throws -> UUID { throw APIError.notConfigured }
    func createRecord(draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func deleteTask(taskID: UUID) async throws {}
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
}
