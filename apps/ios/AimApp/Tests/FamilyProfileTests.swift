import XCTest
@testable import AimApp

final class DueDateDraftTests: XCTestCase {
    private let calendar = PregnancyDateCalculator.calendar
    private var today: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000)) }

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

    func testDueDateModeShowsTheMatchingWeek() {
        var draft = DueDateDraft(currentDueDate: day(62), today: today)
        XCTAssertEqual(draft.dueDate, day(62))
        XCTAssertEqual(draft.gestation?.weeks, 31)
        XCTAssertEqual(draft.gestation?.days, 1)
        XCTAssertNil(draft.validationMessage)
        draft.date = day(10)
        XCTAssertEqual(draft.gestation?.weeks, 38)
    }

    func testCurrentWeekModeComputesTheDueDate() {
        var draft = DueDateDraft(currentDueDate: nil, today: today)
        draft.switchMode(to: .currentWeek)
        draft.weeks = 31
        draft.days = 1
        XCTAssertEqual(draft.dueDate, day(62))
    }

    func testLastPeriodModeAddsTwoHundredEightyDays() {
        var draft = DueDateDraft(currentDueDate: nil, today: today)
        draft.switchMode(to: .lastMenstrualPeriod)
        draft.date = day(-100)
        XCTAssertEqual(draft.dueDate, day(180))
    }

    func testSwitchingModesKeepsTheSameDueDate() {
        var draft = DueDateDraft(currentDueDate: day(62), today: today)
        draft.switchMode(to: .currentWeek)
        XCTAssertEqual(draft.weeks, 31)
        XCTAssertEqual(draft.days, 1)
        draft.switchMode(to: .lastMenstrualPeriod)
        XCTAssertEqual(draft.date, day(62 - 280))
        XCTAssertEqual(draft.dueDate, day(62))
    }

    func testOutOfRangeDatesExplainWhy() {
        var draft = DueDateDraft(currentDueDate: day(281), today: today)
        XCTAssertEqual(draft.validationMessage, "这个日期算出来还没到孕期，请检查一下")
        draft.date = day(-15)
        XCTAssertEqual(draft.validationMessage, "这个日期算出来已经超过 42 周了，请检查一下")
        draft.date = day(-14)
        XCTAssertNil(draft.validationMessage)
        draft.date = day(280)
        XCTAssertNil(draft.validationMessage)
    }
}

final class FamilyActivitySentenceTests: XCTestCase {
    private func item(_ kind: FamilyActivityItem.Kind, title: String = "买产褥垫", viaAgent: Bool = false) -> FamilyActivityItem {
        FamilyActivityItem(
            id: "x", kind: kind, actorName: "老王", title: title, targetType: nil, targetID: nil,
            targetDeleted: false, viaAgent: viaAgent, createdAt: .now)
    }

    func testSentences() {
        XCTAssertEqual(item(.taskCompleted).sentence, "老王 完成了「买产褥垫」")
        XCTAssertEqual(item(.taskCreated, viaAgent: true).sentence, "老王 通过 AIM 新建了「买产褥垫」")
        XCTAssertEqual(item(.memberJoined).sentence, "老王 加入了家庭")
        XCTAssertEqual(item(.dueDateChanged, title: "12月1日").sentence, "老王 把预产期改为 12月1日")
        XCTAssertEqual(item(.memberRemoved, title: "外婆").sentence, "老王 把 外婆 移出了家庭")
    }
}

private final class FamilyRepositoryStub: BusinessRepositoryProtocol, @unchecked Sendable {
    var family = FamilySnapshot(id: UUID(), name: "我们的家", members: [])
    var familyError: Error?
    var pages: [String?: FamilyActivityPage] = [:]
    var updatedDueDate: Date?
    var leaveResult = MeSnapshot(familyID: UUID(), pregnancyID: nil)
    var removeError: Error?

    func fetchToday() async throws -> TodaySnapshot { throw APIError.notConfigured }
    func fetchPlan() async throws -> PlanSnapshot { throw APIError.notConfigured }
    func fetchFamily() async throws -> FamilySnapshot {
        if let familyError { throw familyError }
        return family
    }
    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot { throw APIError.notConfigured }
    func createPregnancy(dueDate: Date) async throws -> UUID { throw APIError.notConfigured }
    func createRecord(draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func deleteRecord(recordID: UUID) async throws {}
    func deleteTask(taskID: UUID) async throws {}
    func fetchSafetyRules() async throws -> [SafetyRule] { [] }
    func fetchContentCollection(_ name: String) async throws -> ContentCollection { throw APIError.notConfigured }
    func createTaskFromRecord(record: RecordItem, title: String, description: String?, dueAt: Date?) async throws -> TaskItem { throw APIError.notConfigured }
    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem { throw APIError.notConfigured }
    func complete(task: TaskItem) async throws -> TaskItem { task }
    func delay(task: TaskItem, until: Date) async throws -> TaskItem { task }
    func schedule(task: TaskItem, at: Date) async throws -> TaskItem { task }
    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem { task }
    func invite(phone: String, role: FamilyRole) async throws {}
    func renameFamily(to name: String) async throws {}
    func updateMyMembership(nickname: String?, role: FamilyRole?) async throws {}
    func requestAccountDeletion(password: String) async throws {}

    func fetchPregnancy() async throws -> PregnancySummary? {
        PregnancySummary(id: UUID(), dueDate: updatedDueDate ?? .now, weeks: 20, days: 0)
    }
    func updateDueDate(_ dueDate: Date) async throws -> PregnancySummary {
        updatedDueDate = dueDate
        return PregnancySummary(id: UUID(), dueDate: dueDate, weeks: 31, days: 1)
    }
    func fetchActivity(before: String?) async throws -> FamilyActivityPage {
        pages[before] ?? FamilyActivityPage(items: [], nextBefore: nil)
    }
    func fetchMyInvitations() async throws -> [MyInvitation] { [] }
    func leaveFamily() async throws -> MeSnapshot { leaveResult }
    func removeMember(accountID: UUID) async throws { if let removeError { throw removeError } }
}

@MainActor
final class FamilyStoreTests: XCTestCase {
    private func activity(_ id: String) -> FamilyActivityItem {
        FamilyActivityItem(
            id: id, kind: .taskCreated, actorName: "阿敏", title: id, targetType: "task", targetID: nil,
            targetDeleted: false, viaAgent: false, createdAt: .now)
    }

    func testLoadingPagesThroughTheActivity() async {
        let repository = FamilyRepositoryStub()
        repository.pages = [
            nil: FamilyActivityPage(items: [activity("a"), activity("b")], nextBefore: "cursor"),
            "cursor": FamilyActivityPage(items: [activity("c")], nextBefore: nil),
        ]
        let store = FamilyStore()
        store.repository = repository
        await store.load()
        XCTAssertEqual(store.activity.map(\.id), ["a", "b"])
        XCTAssertTrue(store.hasMoreActivity)
        await store.loadMoreActivity()
        XCTAssertEqual(store.activity.map(\.id), ["a", "b", "c"])
        XCTAssertFalse(store.hasMoreActivity)
    }

    func testChangingTheDueDateUpdatesThePregnancy() async {
        let repository = FamilyRepositoryStub()
        let store = FamilyStore()
        store.repository = repository
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let saved = await store.updateDueDate(due)
        XCTAssertTrue(saved)
        XCTAssertEqual(store.pregnancy?.dueDate, due)
        XCTAssertEqual(store.pregnancy?.weeks, 31)
    }

    func testBeingRemovedFromTheFamilyIsNoticed() async {
        let repository = FamilyRepositoryStub()
        repository.familyError = APIError.http(status: 403, body: "")
        let store = FamilyStore()
        store.repository = repository
        await store.load()
        XCTAssertTrue(store.lostMembership)
        XCTAssertNil(store.errorMessage)
    }

    func testServerExplanationsAreShownAsIs() async {
        let repository = FamilyRepositoryStub()
        repository.removeError = APIError.http(
            status: 409, body: #"{"error":{"code":"conflict","message":"TA 已经不在家庭里了"}}"#)
        let store = FamilyStore()
        store.repository = repository
        let member = FamilyMember(accountID: UUID(), role: .father, nickname: nil, status: "active", joinedAt: nil)
        let removed = await store.remove(member)
        XCTAssertFalse(removed)
        XCTAssertEqual(store.errorMessage, "TA 已经不在家庭里了")
    }

    func testLeavingReturnsTheNewFamily() async {
        let repository = FamilyRepositoryStub()
        let store = FamilyStore()
        store.repository = repository
        let result = await store.leave()
        XCTAssertEqual(result, repository.leaveResult)
    }
}
