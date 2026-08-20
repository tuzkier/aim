import XCTest

final class CoreJourneyUITests: XCTestCase {
    func testGlobalAgentButtonShowsCurrentTabContext() throws {
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

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 8))
        timelineTab.tap()

        let agentButton = app.buttons["global-agent-button"]
        XCTAssertTrue(agentButton.waitForExistence(timeout: 5))
        agentButton.tap()

        XCTAssertTrue(app.navigationBars["问一问"].waitForExistence(timeout: 3))
        let contextCard = app.descendants(matching: .any).matching(identifier: "agent-current-context").firstMatch
        XCTAssertTrue(contextCard.waitForExistence(timeout: 3))
    }

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

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 8))
        timelineTab.tap()
        if app.buttons["补充孕期信息"].waitForExistence(timeout: 3) {
            app.buttons["补充孕期信息"].tap()
            app.buttons["保存并生成计划"].tap()
        }

        let addRecord = app.buttons["新增记录"]
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
        app.buttons["保存记录"].tap()

        let symptomRecord = app.buttons["record-row-symptom"].firstMatch
        XCTAssertTrue(symptomRecord.waitForExistence(timeout: 5))
        symptomRecord.tap()
        let turnIntoTask = app.buttons["转为待办"]
        reveal(turnIntoTask, in: app)
        XCTAssertTrue(turnIntoTask.exists)
    }

    func testTimelineAnchorsOnTodayAndOffersAgent() throws {
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

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 8))
        timelineTab.tap()

        if app.buttons["补充孕期信息"].waitForExistence(timeout: 3) {
            app.buttons["补充孕期信息"].tap()
            app.buttons["保存并生成计划"].tap()
        }

        let anyWeekHeader = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'timeline-week-header-'"))
            .firstMatch
        XCTAssertTrue(anyWeekHeader.waitForExistence(timeout: 8))

        app.buttons["global-agent-button"].tap()
        XCTAssertTrue(app.navigationBars["问一问"].waitForExistence(timeout: 3))
    }

    func testCompletingATaskOffersToRecordTheResult() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        // Dedicated phone number: this test mutates state (completing a task
        // returns 409 on retry), so it needs its own fresh account rather than
        // sharing the "13800000002" demo account other tests reuse — otherwise
        // repeated runs race against tasks already completed by prior runs.
        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("13800000099")
            app.buttons["开始体验"].tap()
        }

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 8))
        timelineTab.tap()

        if app.buttons["补充孕期信息"].waitForExistence(timeout: 3) {
            app.buttons["补充孕期信息"].tap()
            app.buttons["保存并生成计划"].tap()
        }

        // .swipeActions(edge: .leading) 的「完成」按钮靠向右滑手势展开
        // （手指从左往右拖动内容，露出贴在左侧的 leading 按钮），不是 swipeLeft。
        // Rows for already-completed tasks render but expose no swipe action
        // (TimelineView guards it with `if task.isOpen`), so try each row in
        // turn rather than assuming the first one is still open — this test's
        // own account can accumulate completed tasks across repeated re-runs.
        let taskRows = app.buttons.matching(identifier: "timeline-task-row")
        XCTAssertTrue(taskRows.firstMatch.waitForExistence(timeout: 8))

        let completeAction = app.buttons["完成"]
        var completed = false
        for index in 0..<min(taskRows.count, 5) {
            let row = taskRows.element(boundBy: index)
            row.swipeRight()
            if completeAction.waitForExistence(timeout: 2) {
                completeAction.tap()
                completed = true
                break
            }
            row.swipeLeft()
        }
        XCTAssertTrue(completed, "Expected at least one open task row among the first 5")

        // The toast only appears after TimelineStore.complete(_:) finishes its
        // full reload (four sequential network calls), so give it real headroom
        // instead of the reveal() helper, which swipes to scroll deeply-nested
        // form fields into view — the wrong tool for a fixed bottom overlay.
        // The toast's HStack isn't accessibilityElement(children: .combine), so
        // query broadly the same way testGlobalAgentButtonShowsCurrentTabContext
        // already does for AgentContextCard, rather than app.otherElements[...].
        let toast = app.descendants(matching: .any).matching(identifier: "complete-task-record-prompt").firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 10))

        app.buttons["记一下"].tap()

        XCTAssertTrue(app.navigationBars["新增记录"].waitForExistence(timeout: 3))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if element.waitForExistence(timeout: 1) { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, "Expected \(element) to be reachable")
    }
}
