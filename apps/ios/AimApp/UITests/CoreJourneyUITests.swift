import XCTest

final class CoreJourneyUITests: XCTestCase {
    func testRecordsJourneyCreatesSymptomAndOffersTaskAction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("13800000002")
            app.buttons["开始体验"].tap()
        }

        let todayTab = app.tabBars.buttons["今天"]
        XCTAssertTrue(todayTab.waitForExistence(timeout: 8))
        todayTab.tap()
        if app.buttons["补充预产期"].waitForExistence(timeout: 3) {
            app.buttons["补充预产期"].tap()
            app.buttons["保存并生成计划"].tap()
        }

        let recordsTab = app.tabBars.buttons["记录"]
        XCTAssertTrue(recordsTab.waitForExistence(timeout: 8))
        recordsTab.tap()

        let addRecord = app.navigationBars["记录"].buttons["新增记录"]
        XCTAssertTrue(addRecord.waitForExistence(timeout: 5))
        addRecord.tap()

        let symptomType = app.buttons["record-type-symptom"]
        XCTAssertTrue(symptomType.waitForExistence(timeout: 3))
        symptomType.tap()
        let nausea = app.buttons["record-symptom-恶心"]
        reveal(nausea, in: app)
        nausea.tap()
        let severity = app.buttons["record-severity-1"]
        reveal(severity, in: app)
        severity.tap()
        XCTAssertTrue(app.buttons["record-severity-2"].waitForExistence(timeout: 2))
        app.buttons["record-severity-2"].tap()
        XCTAssertTrue(app.staticTexts["家庭成员可以看到这条记录。"].waitForExistence(timeout: 2))
        app.buttons["保存记录"].tap()

        let symptomRecord = app.staticTexts["恶心"]
        XCTAssertTrue(symptomRecord.waitForExistence(timeout: 5))
        symptomRecord.tap()
        XCTAssertTrue(app.buttons["转为待办"].waitForExistence(timeout: 3))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if element.waitForExistence(timeout: 1) { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, "Expected \(element) to be reachable")
    }
}
