import XCTest
@testable import AimApp

final class TaskComposerViewTests: XCTestCase {
    private let calendar = PregnancyDateCalculator.calendar

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func testDefaultDueIsTodayAtEightPmBeforeEightPm() {
        XCTAssertEqual(TaskComposerView.defaultDueDate(now: at(14, 10, 30)), at(14, 20))
        XCTAssertEqual(TaskComposerView.defaultDueDate(now: at(14, 19, 59)), at(14, 20))
    }

    func testDefaultDueRollsToTomorrowFromEightPm() {
        XCTAssertEqual(TaskComposerView.defaultDueDate(now: at(14, 20, 0)), at(15, 20))
        XCTAssertEqual(TaskComposerView.defaultDueDate(now: at(14, 23, 30)), at(15, 20))
    }
}
