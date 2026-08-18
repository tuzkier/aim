import XCTest
@testable import AimApp

final class TimelineBuilderTests: XCTestCase {
    private let calendar = PregnancyDateCalculator.calendar

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }

    private func task(_ title: String, due: Date?, actor: TaskActor = .system) -> TaskItem {
        TaskItem(id: UUID(), title: title, detail: nil, status: .todo, version: 1,
                 dueAt: due, scheduledFor: nil, assignedMemberID: nil, changedByActor: actor)
    }

    private func record(_ occurred: Date) -> RecordItem {
        RecordItem(
            id: UUID(),
            pregnancyID: UUID(),
            familyID: UUID(),
            authorAccountID: UUID(),
            type: .note,
            occurredAt: occurred,
            visibility: .family,
            title: "记录",
            content: "内容",
            structuredData: .note,
            attachmentRefs: [],
            createdAt: occurred,
            updatedAt: occurred
        )
    }

    func testDerivesLastMenstrualPeriodFromGestationalAge() {
        let asOf = date(2026, 8, 14)
        let lmp = TimelineBuilder.lastMenstrualPeriod(asOf: asOf, weeks: 18, days: 3)
        XCTAssertEqual(calendar.startOfDay(for: lmp), calendar.startOfDay(for: date(2026, 4, 7)))
    }

    func testWeekBoundariesAreSevenDaysWide() {
        let lmp = date(2026, 4, 7)
        XCTAssertEqual(TimelineBuilder.week(for: date(2026, 8, 11), lastMenstrualPeriod: lmp), 18)
        XCTAssertEqual(TimelineBuilder.week(for: date(2026, 8, 17), lastMenstrualPeriod: lmp), 18)
        XCTAssertEqual(TimelineBuilder.week(for: date(2026, 8, 18), lastMenstrualPeriod: lmp), 19)
    }

    func testMergesTasksAndRecordsIntoSameWeekSortedByDate() {
        let lmp = date(2026, 4, 7)
        let weeks = TimelineBuilder.build(
            tasks: [task("散步", due: date(2026, 8, 14))],
            records: [record(date(2026, 8, 12))],
            lastMenstrualPeriod: lmp,
            today: date(2026, 8, 14)
        )
        let current = weeks.first { $0.week == 18 }
        XCTAssertEqual(current?.entries.count, 2)
        if case .record = current?.entries.first {} else { XCTFail("记录应排在前面") }
    }

    func testTaskWithoutAnyDateFallsIntoCurrentWeek() {
        let lmp = date(2026, 4, 7)
        let weeks = TimelineBuilder.build(
            tasks: [task("无日期", due: nil)],
            records: [],
            lastMenstrualPeriod: lmp,
            today: date(2026, 8, 14)
        )
        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(weeks.first?.week, 18)
    }

    func testMarksWeekPositionRelativeToToday() {
        let lmp = date(2026, 4, 7)
        let weeks = TimelineBuilder.build(
            tasks: [
                task("过去", due: date(2026, 8, 5)),
                task("现在", due: date(2026, 8, 14)),
                task("未来", due: date(2026, 8, 20))
            ],
            records: [],
            lastMenstrualPeriod: lmp,
            today: date(2026, 8, 14)
        )
        XCTAssertEqual(weeks.map(\.position), [.past, .current, .future])
        XCTAssertEqual(weeks.map(\.week), [17, 18, 19])
    }

    func testCurrentWeekIsAlwaysPresentEvenWhenEmpty() {
        let lmp = date(2026, 4, 7)
        let weeks = TimelineBuilder.build(
            tasks: [], records: [], lastMenstrualPeriod: lmp, today: date(2026, 8, 14)
        )
        XCTAssertEqual(weeks.map(\.week), [18])
        XCTAssertTrue(weeks[0].entries.isEmpty)
    }
}
