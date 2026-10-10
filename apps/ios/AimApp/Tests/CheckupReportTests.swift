import XCTest
import UIKit
@testable import AimApp

@MainActor
final class CheckupReportTests: XCTestCase {
    private let reportID = UUID(uuidString: "0B6C1A2E-1111-4A2B-9C3D-123456789ABC")!

    private func report(
        id: UUID = UUID(), daysAgo: Int = 0, visibility: RecordVisibility = .family,
        metrics: CheckupMetrics = CheckupMetrics(), otherItems: [CheckupOtherItem] = []
    ) -> RecordItem {
        let when = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return RecordItem(
            id: id, pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .checkup, occurredAt: when, visibility: visibility, title: nil, content: nil,
            structuredData: .checkup(CheckupRecordData(
                hospital: "市一医院", examItems: "常规产检", result: nil, doctorAdvice: nil,
                metrics: metrics, otherItems: otherItems)),
            attachmentRefs: [], createdAt: when, updatedAt: when)
    }

    private func question(_ text: String, reportID: UUID?) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .question, occurredAt: .now, visibility: .family, title: nil, content: text,
            structuredData: .question(QuestionRecordData(answered: false, answer: nil, reportID: reportID)),
            attachmentRefs: [], createdAt: .now, updatedAt: .now)
    }

    private let protein = CheckupOtherItem(name: "尿蛋白", value: "+", reference: "阴性", flag: .abnormal)
    private let glucose = CheckupOtherItem(name: "尿糖", value: "阴性", reference: "阴性", flag: nil)
    private let platelets = CheckupOtherItem(
        name: "血小板", value: "98", unit: "10^9/L", reference: "125-350", flag: .low)

    // MARK: - 与上次对比

    func testComparisonAgainstThePreviousReport() {
        let current = CheckupRecordData(
            hospital: nil, examItems: nil, result: nil, doctorAdvice: nil,
            metrics: CheckupMetrics(weightKg: 61.3, systolic: 112, fetalHeartRate: 145))
        let previous = CheckupRecordData(
            hospital: nil, examItems: nil, result: nil, doctorAdvice: nil,
            metrics: CheckupMetrics(weightKg: 60.5, systolic: 118, fetalHeartRate: 145))

        let deltas = CheckupComparison.make(current: current, previous: previous)

        XCTAssertEqual(deltas.map(\.kind), [.weight, .systolic, .fetalHeartRate], "只列这次测了的，按固定顺序")
        XCTAssertEqual(deltas[0].value, 61.3)
        XCTAssertEqual(deltas[0].delta!, 0.8, accuracy: 0.0001)
        XCTAssertEqual(deltas[0].unit, "kg")
        XCTAssertEqual(deltas[0].deltaText, "↑ 0.8 kg")
        XCTAssertEqual(deltas[1].deltaText, "↓ 6 mmHg")
        XCTAssertEqual(deltas[2].deltaText, "持平")
    }

    func testFirstReportHasNoComparison() {
        let current = CheckupRecordData(
            hospital: nil, examItems: nil, result: nil, doctorAdvice: nil,
            metrics: CheckupMetrics(weightKg: 61.3))

        let deltas = CheckupComparison.make(current: current, previous: nil)

        XCTAssertEqual(deltas.count, 1)
        XCTAssertNil(deltas[0].delta)
        XCTAssertNil(deltas[0].deltaText)
    }

    /// 上次没测这项，就没得比——不能当成 0 算出一个大涨幅。
    func testAMetricMissingLastTimeHasNoDelta() {
        let current = CheckupRecordData(
            hospital: nil, examItems: nil, result: nil, doctorAdvice: nil,
            metrics: CheckupMetrics(weightKg: 61, hemoglobin: 112))
        let previous = CheckupRecordData(
            hospital: nil, examItems: nil, result: nil, doctorAdvice: nil,
            metrics: CheckupMetrics(weightKg: 60))

        let deltas = CheckupComparison.make(current: current, previous: previous)

        XCTAssertEqual(deltas.map(\.kind), [.weight, .hemoglobin])
        XCTAssertEqual(deltas[0].delta!, 1, accuracy: 0.0001)
        XCTAssertNil(deltas[1].delta)
    }

    /// 上一份是时间上早于这份的最近一份产检，与列表顺序无关。
    func testPreviousReportIsTheLatestOneBeforeThisOne() {
        let old = report(daysAgo: 30, metrics: CheckupMetrics(weightKg: 58))
        let last = report(daysAgo: 14, metrics: CheckupMetrics(weightKg: 60))
        let current = report(daysAgo: 0, metrics: CheckupMetrics(weightKg: 61))
        let later = report(daysAgo: -3, metrics: CheckupMetrics(weightKg: 62))

        let previous = CheckupReport.previous(of: current, in: [later, old, current, last])

        XCTAssertEqual(previous?.metrics.weightKg, 60)
        XCTAssertNil(CheckupReport.previous(of: old, in: [later, old, current, last]))
    }

    // MARK: - 其他化验项

    func testLibraryCardShowsTheLatestReportsFlags() {
        let old = report(daysAgo: 14, otherItems: [protein, platelets])
        let latest = report(daysAgo: 1, otherItems: [protein, glucose])
        let summary = LibraryCategoryID.checkups.summary(from: LibrarySnapshot(records: [old, latest]))
        XCTAssertEqual(summary.headline, "2 次记录")
        XCTAssertEqual(summary.tags, ["最近报告 1 项异常"])
        XCTAssertEqual(LibraryCategoryID.checkups.title, "产检与报告")
    }

    func testFlaggedItemsComeFirstAndKeepTheirOrder() {
        let data = CheckupRecordData(
            hospital: nil, examItems: nil, result: nil, doctorAdvice: nil,
            otherItems: [glucose, protein, platelets])

        XCTAssertEqual(CheckupReport.sortedItems(data).map(\.name), ["尿蛋白", "血小板", "尿糖"])
        XCTAssertEqual(CheckupReport.flaggedItems(data).map(\.name), ["尿蛋白", "血小板"])
    }

    // MARK: - 把异常项加入想问医生

    func testEachFlaggedItemBecomesAQuestionPointingBackAtTheReport() {
        let item = report(id: reportID, otherItems: [protein, glucose, platelets])

        let drafts = CheckupReport.missingQuestions(for: item, in: [item], now: .now)

        XCTAssertEqual(drafts.count, 2)
        XCTAssertTrue(drafts.allSatisfy { $0.type == .question })
        XCTAssertTrue(drafts[0].content!.contains("尿蛋白"))
        XCTAssertTrue(drafts[1].content!.contains("血小板"))
        for draft in drafts {
            guard case let .question(data) = draft.structuredData else { return XCTFail("应当是问题") }
            XCTAssertEqual(data.reportID, reportID)
            XCTAssertFalse(data.answered)
        }
    }

    /// 已经加过（或 AIM 读报告时已经建了）的不重复加：同一份报告、问题里提到了这一项。
    func testItemsAlreadyAskedAboutAreNotAddedAgain() {
        let item = report(id: reportID, otherItems: [protein, platelets])
        let records = [
            item,
            question("尿蛋白一个加号要紧吗？", reportID: reportID),
            // 别的报告里问过血小板，不算这份报告的。
            question("血小板偏低怎么办", reportID: UUID()),
        ]

        let drafts = CheckupReport.missingQuestions(for: item, in: records, now: .now)

        XCTAssertEqual(drafts.count, 1)
        XCTAssertTrue(drafts[0].content!.contains("血小板"))
    }

    func testReportWithoutFlagsHasNothingToAdd() {
        let item = report(id: reportID, otherItems: [glucose])

        XCTAssertTrue(CheckupReport.missingQuestions(for: item, in: [item], now: .now).isEmpty)
    }

    func testAddingQuestionsSavesOnlyTheMissingOnes() async {
        let item = report(id: reportID, otherItems: [protein, platelets])
        let existing = [item, question("尿蛋白要复查吗", reportID: reportID)]
        let repository = RecordingRepository(records: existing)
        let store = RecordStore(repository: repository)
        // 筛选产检后快照里没有问题，也必须从完整记录判断哪些已经加过。
        store.snapshot = RecordSnapshot(records: [item])

        let added = await store.addQuestions(forReport: item)

        XCTAssertEqual(added, 1)
        let created = await repository.created
        XCTAssertEqual(created.count, 1)
        XCTAssertTrue(created[0].content!.contains("血小板"))

        // 再点一次：刚加的已经在快照里，不会再加。
        let again = await store.addQuestions(forReport: item)
        XCTAssertEqual(again, 0)
        let createdAfter = await repository.created
        XCTAssertEqual(createdAfter.count, 1)
    }

    func testAFailedRefreshDoesNotCreateDuplicateQuestionsFromAnOldSnapshot() async {
        let item = report(id: reportID, otherItems: [protein])
        let repository = RecordingRepository(failFetch: true)
        let store = RecordStore(repository: repository)
        store.snapshot = RecordSnapshot(records: [item])

        let added = await store.addQuestions(forReport: item)

        XCTAssertEqual(added, 0)
        XCTAssertNotNil(store.errorMessage)
        let created = await repository.created
        XCTAssertTrue(created.isEmpty)
    }

    // MARK: - 问 AIM

    func testAgentContextNamesTheReportAndItsFlaggedItems() {
        let item = report(id: reportID, otherItems: [protein, glucose, platelets])

        let context = CheckupReport.agentContext(for: item)

        XCTAssertTrue(context.title.hasPrefix("报告："), context.title)
        XCTAssertTrue(context.summary.contains("记录编号：0b6c1a2e-1111-4a2b-9c3d-123456789abc"), context.summary)
        XCTAssertFalse(context.summary.contains(reportID.uuidString))
        XCTAssertTrue(context.summary.contains("尿蛋白"))
        XCTAssertTrue(context.summary.contains("血小板"))
        XCTAssertFalse(context.summary.contains("尿糖"), "没标记的项不放进异常项")
    }

    // MARK: - 编辑权限

    func testFamilyRecordsCanBeEditedByAnyMemberButVisibilityOnlyByTheAuthor() {
        let author = UUID()
        let other = UUID()
        let family = RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: author,
            type: .checkup, occurredAt: .now, visibility: .family, title: nil, content: nil,
            structuredData: .note, attachmentRefs: [], createdAt: .now, updatedAt: .now)
        let mine = RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: author,
            type: .checkup, occurredAt: .now, visibility: .private, title: nil, content: nil,
            structuredData: .note, attachmentRefs: [], createdAt: .now, updatedAt: .now)

        XCTAssertTrue(family.isEditable(by: author))
        XCTAssertTrue(family.isEditable(by: other))
        XCTAssertFalse(family.isEditable(by: nil))
        XCTAssertTrue(mine.isEditable(by: author))
        XCTAssertFalse(mine.isEditable(by: other))

        XCTAssertTrue(family.canChangeVisibility(by: author))
        XCTAssertFalse(family.canChangeVisibility(by: other))
    }

    // MARK: - 带照片保存

    /// 先逐张上传，再建记录并挂上上传得到的编号。
    func testSavingWithPhotosUploadsFirstThenAttachesThem() async {
        let repository = RecordingRepository()
        let store = RecordStore(repository: repository)
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }.pngData()!
        let draft = RecordDraft(
            type: .checkup, occurredAt: .now, visibility: .family, title: nil, content: nil,
            structuredData: .checkup(CheckupRecordData(
                hospital: "市一医院", examItems: nil, result: nil, doctorAdvice: nil)))

        let saved = await store.save(draft, photos: [photo, photo])

        XCTAssertTrue(saved)
        let uploads = await repository.uploads
        XCTAssertEqual(uploads.count, 2)
        XCTAssertTrue(uploads.allSatisfy { $0.starts(with: [0xFF, 0xD8]) }, "上传的是 JPEG")
        let created = await repository.created
        let uploaded = await repository.uploadedIDs
        XCTAssertEqual(created.first?.attachmentIDs, uploaded)
    }

    func testAFailedUploadDoesNotCreateTheRecord() async {
        let repository = RecordingRepository(failUploads: true)
        let store = RecordStore(repository: repository)
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }.pngData()!
        let draft = RecordDraft(
            type: .checkup, occurredAt: .now, visibility: .family, title: nil, content: nil,
            structuredData: .checkup(CheckupRecordData(
                hospital: "市一医院", examItems: nil, result: nil, doctorAdvice: nil)))

        let saved = await store.save(draft, photos: [photo])

        XCTAssertFalse(saved)
        XCTAssertNotNil(store.errorMessage)
        let created = await repository.created
        XCTAssertTrue(created.isEmpty)
    }
}

private actor RecordingRepository: BusinessRepositoryProtocol {
    private(set) var created: [RecordDraft] = []
    private(set) var uploads: [Data] = []
    private(set) var uploadedIDs: [UUID] = []
    private let failUploads: Bool
    private let records: [RecordItem]
    private let failFetch: Bool

    init(failUploads: Bool = false, records: [RecordItem] = [], failFetch: Bool = false) {
        self.failUploads = failUploads
        self.records = records
        self.failFetch = failFetch
    }

    func uploadAttachment(jpeg: Data) async throws -> UUID {
        if failUploads { throw APIError.invalidResponse }
        uploads.append(jpeg)
        let id = UUID()
        uploadedIDs.append(id)
        return id
    }

    func createRecord(draft: RecordDraft) async throws -> RecordItem {
        created.append(draft)
        return RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: draft.type, occurredAt: draft.occurredAt, visibility: draft.visibility,
            title: draft.title, content: draft.content, structuredData: draft.structuredData,
            attachmentRefs: draft.attachmentIDs.map { $0.uuidString.lowercased() },
            createdAt: .now, updatedAt: .now)
    }

    func fetchToday() async throws -> TodaySnapshot { throw APIError.invalidResponse }
    func fetchPlan() async throws -> PlanSnapshot { throw APIError.invalidResponse }
    func fetchFamily() async throws -> FamilySnapshot { throw APIError.invalidResponse }
    func createPregnancy(dueDate: Date) async throws -> UUID { throw APIError.invalidResponse }
    func complete(task: TaskItem) async throws -> TaskItem { throw APIError.invalidResponse }
    func delay(task: TaskItem, until: Date) async throws -> TaskItem { throw APIError.invalidResponse }
    func schedule(task: TaskItem, at: Date) async throws -> TaskItem { throw APIError.invalidResponse }
    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem { throw APIError.invalidResponse }
    func invite(phone: String, role: FamilyRole) async throws { throw APIError.invalidResponse }
    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot {
        if failFetch { throw APIError.invalidResponse }
        return RecordSnapshot(records: records + created.map { draft in
            RecordItem(
                id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
                type: draft.type, occurredAt: draft.occurredAt, visibility: draft.visibility,
                title: draft.title, content: draft.content, structuredData: draft.structuredData,
                attachmentRefs: [], createdAt: .now, updatedAt: .now)
        })
    }
    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem { throw APIError.invalidResponse }
    func deleteRecord(recordID: UUID) async throws { throw APIError.invalidResponse }
    func deleteTask(taskID: UUID) async throws { throw APIError.invalidResponse }
    func fetchSafetyRules() async throws -> [SafetyRule] { [] }
    func fetchContentCollection(_ name: String) async throws -> ContentCollection {
        ContentCollection(id: name, source: "test", sourceURL: "", items: [])
    }
    func createTaskFromRecord(record: RecordItem, title: String, description: String?, dueAt: Date?) async throws -> TaskItem { throw APIError.invalidResponse }
    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem { throw APIError.invalidResponse }
    func renameFamily(to name: String) async throws {}
    func updateMyMembership(nickname: String?, role: FamilyRole?) async throws {}
    func requestAccountDeletion(password: String) async throws { throw APIError.notConfigured }
}
