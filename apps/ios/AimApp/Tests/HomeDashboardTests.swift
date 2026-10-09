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
