import XCTest
@testable import AimApp

@MainActor
final class TimelineStoreTests: XCTestCase {
    func testFilterAllKeepsTasksAndRecords() {
        XCTAssertTrue(TimelineFilter.all.accepts(entryKind: .task))
        XCTAssertTrue(TimelineFilter.all.accepts(entryKind: .record(.checkup)))
    }

    func testFilterTasksExcludesRecords() {
        XCTAssertTrue(TimelineFilter.tasks.accepts(entryKind: .task))
        XCTAssertFalse(TimelineFilter.tasks.accepts(entryKind: .record(.note)))
    }

    func testFilterCheckupOnlyAcceptsCheckupRecords() {
        XCTAssertFalse(TimelineFilter.checkup.accepts(entryKind: .task))
        XCTAssertTrue(TimelineFilter.checkup.accepts(entryKind: .record(.checkup)))
        XCTAssertFalse(TimelineFilter.checkup.accepts(entryKind: .record(.symptom)))
    }

    func testFocusTaskPrefersEarliestOpenTaskInCurrentWeek() {
        let store = TimelineStore.preview()
        XCTAssertEqual(store.focusTask?.title, "核对检查所需材料")
    }

    func testAssigneeNameResolvesFromFamilyMembers() {
        let store = TimelineStore.preview()
        let motherID = store.familyMembers.first { $0.role == .mother }?.accountID
        XCTAssertEqual(store.assigneeName(for: motherID), "妈妈")
        XCTAssertNil(store.assigneeName(for: nil))
        XCTAssertNil(store.assigneeName(for: UUID()))
    }
}
