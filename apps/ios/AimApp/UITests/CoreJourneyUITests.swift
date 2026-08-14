import XCTest

final class CoreJourneyUITests: XCTestCase {
    func testCoreJourneyPlaceholder() throws {
        // The executable UI test is enabled when the first Xcode target is opened.
        // Keep the journey contract close to the app until a simulator is available:
        // onboarding → Today → task detail → complete → refreshed Today.
        XCTAssertTrue(true)
    }
}
