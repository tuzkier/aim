import XCTest
@testable import AimApp

final class TaskDateTextTests: XCTestCase {
    private let calendar = PregnancyDateCalculator.calendar

    /// 2026-09-14 是周一。
    private let now = PregnancyDateCalculator.calendar.date(
        from: DateComponents(year: 2026, month: 9, day: 14, hour: 10, minute: 30))!

    private func at(_ day: Int, _ hour: Int = 9, _ minute: Int = 0, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func testTodayTomorrowYesterday() {
        XCTAssertEqual(TaskDateText.label(for: at(14, 19, 30), now: now), "今天 19:30")
        XCTAssertEqual(TaskDateText.label(for: at(15, 8), now: now), "明天 08:00")
        XCTAssertEqual(TaskDateText.label(for: at(13, 20), now: now), "昨天 20:00")
    }

    func testWithinAWeekUsesWeekday() {
        XCTAssertEqual(TaskDateText.label(for: at(16, 9), now: now), "周三 09:00")
        XCTAssertEqual(TaskDateText.label(for: at(20, 9), now: now), "周日 09:00")
    }

    func testSevenDaysOrMoreUsesCalendarDate() {
        XCTAssertEqual(TaskDateText.label(for: at(21, 9), now: now), "9月21日 09:00")
        XCTAssertEqual(TaskDateText.label(for: at(2, 9, month: 10), now: now), "10月2日 09:00")
    }

    func testPastDaysCountBackUpToAWeek() {
        XCTAssertEqual(TaskDateText.label(for: at(11, 9), now: now), "3 天前 09:00")
        XCTAssertEqual(TaskDateText.label(for: at(7, 9), now: now), "7 天前 09:00")
        XCTAssertEqual(TaskDateText.label(for: at(6, 9), now: now), "9月6日 09:00")
    }

    func testEndOfDaySentinelHidesTime() {
        let due = TaskDateText.endOfDay(at(14))
        XCTAssertTrue(TaskDateText.isEndOfDaySentinel(due))
        XCTAssertEqual(TaskDateText.label(for: due, now: now), "今天")
        XCTAssertFalse(TaskDateText.isEndOfDaySentinel(at(14, 23, 58)))
    }

    func testEndOfDayIsTwentyThreeFiftyNine() {
        let components = calendar.dateComponents([.hour, .minute, .second], from: TaskDateText.endOfDay(at(14, 3)))
        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 59)
        XCTAssertEqual(components.second, 0)
    }
}
