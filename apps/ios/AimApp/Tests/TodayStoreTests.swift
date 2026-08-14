import XCTest

@MainActor
final class TodayStoreTests: XCTestCase {
    func testPreviewSnapshotKeepsPriorityTaskAndUpcomingTasksSeparate() {
        let store = TodayStore.preview()
        XCTAssertNotNil(store.snapshot?.priorityTask)
        XCTAssertEqual(store.snapshot?.upcomingTasks.count, 2)
        XCTAssertEqual(store.snapshot?.familyOpenTaskCount, 4)
    }
}
