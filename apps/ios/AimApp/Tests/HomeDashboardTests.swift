import XCTest
@testable import AimApp

final class WeeklyContentTests: XCTestCase {
    private func week(_ n: Int) -> WeekContent {
        WeekContent(week: n, fruit: "🍋", fruitName: "柠檬\(n)", lengthCm: Double(n), weightG: Double(n * 10),
                    baby: "宝宝", mom: "妈妈", tips: ["建议"])
    }

    private var book: WeeklyContentBook {
        WeeklyContentBook(source: "来源", sourceURL: "https://example.com", reviewedAt: "2026-10-08",
                          weeks: (4...42).map(week))
    }

    func testStagesSplitAt14And28Weeks() {
        XCTAssertEqual(PregnancyStage(weeks: 13), .early)
        XCTAssertEqual(PregnancyStage(weeks: 14), .middle)
        XCTAssertEqual(PregnancyStage(weeks: 27), .middle)
        XCTAssertEqual(PregnancyStage(weeks: 28), .late)
        XCTAssertEqual(PregnancyStage.late.title, "孕晚期")
    }

    func testProgressIsCappedAndCountsDaysLeft() {
        XCTAssertEqual(PregnancyProgress(weeks: 0, days: 0).fraction, 0)
        XCTAssertEqual(PregnancyProgress(weeks: 20, days: 0).fraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(PregnancyProgress(weeks: 40, days: 0).fraction, 1)
        XCTAssertEqual(PregnancyProgress(weeks: 45, days: 0).fraction, 1)
        XCTAssertEqual(PregnancyProgress(weeks: 31, days: 1).daysLeft, 62)
        XCTAssertEqual(PregnancyProgress(weeks: 41, days: 0).daysLeft, -7)
        // 孕晚期从 28 周到 40 周，34 周正好走了一半
        XCTAssertEqual(PregnancyProgress(weeks: 34, days: 0).stageFraction, 0.5, accuracy: 0.0001)
    }

    func testWeeksOutsideTheBookFallBack() {
        XCTAssertEqual(book.content(forWeek: 2), WeeklyContentBook.earlyFallback)
        XCTAssertEqual(book.content(forWeek: 31).fruitName, "柠檬31")
        XCTAssertEqual(book.content(forWeek: 45).week, 42)
    }

    func testTheCacheRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = WeeklyContentCache(directory: directory)
        XCTAssertNil(cache.load())
        try cache.save(book)
        XCTAssertEqual(cache.load(), book)
    }

    func testDecodesTheServerShape() throws {
        let json = #"{"source":"s","source_url":"https://x","reviewed_at":"2026-10-08","weeks":[{"week":4,"fruit":"🌱","fruit_name":"一粒芝麻","length_cm":null,"weight_g":null,"baby":"b","mom":"m","tips":["t"]}]}"#
        let decoded = try JSONDecoder().decode(WeeklyContentBook.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.weeks.first?.fruitName, "一粒芝麻")
        XCTAssertNil(decoded.weeks.first?.lengthCm)
    }
}

final class HomeTodaySelectionTests: XCTestCase {
    private let calendar = TimelineBuilder.calendar
    private var now: Date { calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))! }

    private func task(_ title: String, dueInDays: Int?, done: Bool = false) -> TaskItem {
        TaskItem(id: UUID(), title: title, detail: nil, status: done ? .completed : .todo, version: 1,
                 dueAt: dueInDays.map { calendar.date(byAdding: .day, value: $0, to: now)! },
                 scheduledFor: nil, assignedMemberID: nil, changedByActor: .account)
    }

    func testOverdueFirstAtMostThreeAndTheTotal() {
        let tasks = [task("今天1", dueInDays: 0), task("逾期", dueInDays: -2), task("今天2", dueInDays: 0),
                     task("没日期", dueInDays: nil), task("明天", dueInDays: 1), task("已完成", dueInDays: 0, done: true)]
        let selection = HomeDashboardStore.todaySelection(tasks: tasks, now: now)
        XCTAssertEqual(selection.shown.map(\.title), ["逾期", "今天1", "今天2"])
        XCTAssertEqual(selection.total, 4)
        XCTAssertNil(selection.next)
    }

    func testNothingTodayPointsToTheNextOne() {
        let tasks = [task("下周", dueInDays: 7), task("后天", dueInDays: 2)]
        let selection = HomeDashboardStore.todaySelection(tasks: tasks, now: now)
        XCTAssertTrue(selection.shown.isEmpty)
        XCTAssertEqual(selection.total, 0)
        XCTAssertEqual(selection.next?.title, "后天")
    }

    func testGreetingFollowsTheTimeOfDay() {
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
        }
        XCTAssertEqual(HomeDashboardStore.greeting(at: at(4, 59)), "晚上好")
        XCTAssertEqual(HomeDashboardStore.greeting(at: at(5)), "早上好")
        XCTAssertEqual(HomeDashboardStore.greeting(at: at(11)), "中午好")
        XCTAssertEqual(HomeDashboardStore.greeting(at: at(13)), "下午好")
        XCTAssertEqual(HomeDashboardStore.greeting(at: at(18)), "晚上好")
    }
}

@MainActor
final class HomeDashboardStoreHospitalTripTests: XCTestCase {
    func testHomeStoreLoadsHospitalTrips() async {
        // 假仓库只对 .hospitalTrip 返回这条去医院记录，其他类型返回空。
        let repository = FakeHomeRepository()
        repository.records = [FakeHomeRepository.trip(), FakeHomeRepository.item(type: .symptom)]
        let store = HomeDashboardStore()
        store.repository = repository
        await store.load()
        XCTAssertEqual(store.hospitalTrips.count, 1)
        XCTAssertEqual(store.hospitalTrips.first?.type, .hospitalTrip)
    }

    func testFailingTripsKeepThePreviousValue() async {
        let repository = FakeHomeRepository()
        repository.records = [FakeHomeRepository.trip()]
        let store = HomeDashboardStore()
        store.repository = repository
        await store.load()
        repository.failRecords = true
        await store.load()
        XCTAssertEqual(store.hospitalTrips.count, 1)
    }

    func testWithdrawDeletesRemovesAndBroadcasts() async {
        let repository = FakeHomeRepository()
        let trip = FakeHomeRepository.trip()
        repository.records = [trip]
        let store = HomeDashboardStore()
        store.repository = repository
        await store.load()

        let broadcast = expectation(forNotification: .aimDataChanged, object: nil) { note in
            (note.userInfo?["kinds"] as? [String]) == ["record"]
        }
        let ok = await store.withdraw(trip)
        XCTAssertTrue(ok)
        XCTAssertEqual(repository.deletedIDs, [trip.id])
        XCTAssertTrue(store.hospitalTrips.isEmpty)
        await fulfillment(of: [broadcast], timeout: 1)
    }

    func testFailedWithdrawKeepsTheTrip() async {
        let repository = FakeHomeRepository()
        let trip = FakeHomeRepository.trip()
        repository.records = [trip]
        let store = HomeDashboardStore()
        store.repository = repository
        await store.load()
        repository.failDeletes = true
        let ok = await store.withdraw(trip)
        XCTAssertFalse(ok)
        XCTAssertEqual(store.hospitalTrips.map(\.id), [trip.id])
    }
}

/// 只实现首页去医院横幅用到的接口，写法照 FetalMovementStoreTests 的 FakeFetalRepository；
/// 其余必需方法一律 `throw APIError.notConfigured`——首页各块独立报错，不影响这里要测的。
private final class FakeHomeRepository: BusinessRepositoryProtocol, @unchecked Sendable {
    var records: [RecordItem] = []
    var failRecords = false
    var failDeletes = false
    private(set) var deletedIDs: [UUID] = []

    static func item(type: RecordType) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: type, occurredAt: .now, visibility: .family,
            title: "记录", content: nil, structuredData: .note,
            attachmentRefs: [], createdAt: .now, updatedAt: .now)
    }

    static func trip() -> RecordItem {
        let draft = HospitalTrip.draft(reason: .contractions, note: "", contractionRecordID: nil, at: .now)
        return RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: draft.type, occurredAt: draft.occurredAt, visibility: draft.visibility,
            title: draft.title, content: draft.content, structuredData: draft.structuredData,
            attachmentRefs: [], createdAt: .now, updatedAt: .now)
    }

    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot {
        if failRecords { throw APIError.invalidResponse }
        return RecordSnapshot(records: records.filter { type == nil || $0.type == type })
    }

    func createRecord(draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }

    func deleteRecord(recordID: UUID) async throws {
        if failDeletes { throw APIError.invalidResponse }
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
