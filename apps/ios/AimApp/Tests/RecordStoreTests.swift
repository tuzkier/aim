import XCTest
@testable import AimApp

@MainActor
final class RecordStoreTests: XCTestCase {
    func testAttachmentRequestCarriesTheLoginAndPointsAtTheImage() throws {
        let environment = APIEnvironment(
            baseURL: URL(string: "http://127.0.0.1:8100")!,
            eveBaseURL: URL(string: "http://127.0.0.1:2210")!,
            bearerToken: "aim.v1.token",
            accountID: nil,
            familyID: nil,
            pregnancyID: nil
        )
        let id = "44444444-4444-4444-8444-444444444444"
        let request = try XCTUnwrap(AttachmentRequest.make(id: id, environment: environment))
        XCTAssertEqual(request.url?.path, "/api/v1/attachments/\(id)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer aim.v1.token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/*")
        // 附件引用只能是编号；不是编号的（旧数据、外部地址）一律不去请求。
        XCTAssertNil(AttachmentRequest.make(id: "uploads/a.jpg", environment: environment))
    }

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

    /// 在记录详情里问 AIM：上下文要带这条记录的小写编号，AIM 才能用
    /// `[[record:<编号>|…]]` 引用它（网页端只认小写，与 API 返回的编号一致）。
    func testRecordAgentContextCarriesItsLowercasedID() {
        let id = UUID(uuidString: "0B6C1A2E-1111-4A2B-9C3D-123456789ABC")!
        let record = RecordItem(
            id: id, pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .checkup, occurredAt: .now, visibility: .family,
            title: nil, content: nil,
            structuredData: .checkup(CheckupRecordData(
                hospital: "市一医院", examItems: "常规", result: "正常", doctorAdvice: "按时复查")),
            attachmentRefs: [], createdAt: .now, updatedAt: .now
        )

        let context = record.agentContext

        XCTAssertEqual(context.title, "记录")
        let lines = context.summary.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "产检：常规")
        XCTAssertTrue(lines.contains("记录编号：0b6c1a2e-1111-4a2b-9c3d-123456789abc"), context.summary)
        XCTAssertFalse(context.summary.contains(id.uuidString), "不带大写编号")
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
    func requestAccountDeletion(password: String) async throws { throw APIError.notConfigured }
}
