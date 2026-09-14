import XCTest
@testable import AimApp

@MainActor
final class RecordStoreTests: XCTestCase {
    func testPreviewRecordsAreSortedNewestFirst() {
        let records = RecordStore.preview().snapshot?.records ?? []

        XCTAssertEqual(records.map(\.occurredAt), records.map(\.occurredAt).sorted(by: >))
    }

    func testSavePreservesDraftWhenRepositoryFails() async {
        let draft = RecordDraft(
            type: .symptom,
            occurredAt: .now,
            visibility: .family,
            title: nil,
            content: nil,
            structuredData: .symptom(SymptomRecordData(symptoms: ["恶心"], severity: 2, note: "上午更明显"))
        )
        let store = RecordStore(repository: FailingRecordRepository())

        let saved = await store.save(draft)
        XCTAssertFalse(saved)
        XCTAssertEqual(store.draft, draft)
        XCTAssertNotNil(store.errorMessage)
    }

    func testLoadExposesErrorInsteadOfAnEmptySnapshot() async {
        let store = RecordStore(repository: FailingRecordRepository())

        await store.load()

        XCTAssertNil(store.snapshot)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }

    func testFailedRefreshPreservesPreviouslyLoadedSnapshot() async {
        let store = RecordStore.preview()
        let previousSnapshot = store.snapshot
        store.repository = FailingRecordRepository()

        await store.load()

        XCTAssertEqual(store.snapshot, previousSnapshot)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.isLoading)
    }
}

private actor FailingRecordRepository: BusinessRepositoryProtocol {
    func fetchToday() async throws -> TodaySnapshot { throw APIError.invalidResponse }
    func fetchPlan() async throws -> PlanSnapshot { throw APIError.invalidResponse }
    func fetchFamily() async throws -> FamilySnapshot { throw APIError.invalidResponse }
    func createPregnancy(dueDate: Date) async throws -> UUID { throw APIError.invalidResponse }
    func complete(task: TaskItem) async throws -> TaskItem { throw APIError.invalidResponse }
    func delay(task: TaskItem, until: Date) async throws -> TaskItem { throw APIError.invalidResponse }
    func schedule(task: TaskItem, at: Date) async throws -> TaskItem { throw APIError.invalidResponse }
    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem { throw APIError.invalidResponse }
    func invite(phone: String, role: FamilyRole) async throws { throw APIError.invalidResponse }
    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot { throw APIError.invalidResponse }
    func createRecord(draft: RecordDraft) async throws -> RecordItem { throw APIError.invalidResponse }
    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem { throw APIError.invalidResponse }
    func deleteRecord(recordID: UUID) async throws { throw APIError.invalidResponse }
    func deleteTask(taskID: UUID) async throws { throw APIError.invalidResponse }
    func fetchSafetyRules() async throws -> [SafetyRule] { [] }
    func fetchContentCollection(_ name: String) async throws -> ContentCollection {
        ContentCollection(id: name, source: "test", sourceURL: "", items: [])
    }
    func createTaskFromRecord(record: RecordItem, title: String, description: String?, dueAt: Date?) async throws -> TaskItem { throw APIError.invalidResponse }
    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem { throw APIError.invalidResponse }

    // 这两个替身不涉及家庭编辑，实现成空操作即可；
    // 真要用到时会因为断言不成立而暴露，而不是被静默吞掉。
    func renameFamily(to name: String) async throws {}
    func updateMyMembership(nickname: String?, role: FamilyRole?) async throws {}
}
