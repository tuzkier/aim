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
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }

        completePregnancySetup(in: app)

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 15))
        timelineTab.tap()

        let agentButton = app.buttons["global-agent-button"]
        XCTAssertTrue(agentButton.waitForExistence(timeout: 5))
        agentButton.tap()

        XCTAssertTrue(app.navigationBars["AIM"].waitForExistence(timeout: 3))
        let contextCard = app.descendants(matching: .any).matching(identifier: "agent-current-context").firstMatch
        XCTAssertTrue(contextCard.waitForExistence(timeout: 3))
    }

    func testRecordsJourneyCreatesSymptomAndOffersTaskAction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        // 每个用例都用随机手机号：测试不该占用登录页预填的演示号，
        // 否则真人点进来看到的是测试残留数据。
        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }

        completePregnancySetup(in: app)

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 15))
        timelineTab.tap()

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
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }

        completePregnancySetup(in: app)

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 15))
        timelineTab.tap()

        let anyWeekHeader = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'timeline-week-header-'"))
            .firstMatch
        XCTAssertTrue(anyWeekHeader.waitForExistence(timeout: 8))

        app.buttons["global-agent-button"].tap()
        XCTAssertTrue(app.navigationBars["AIM"].waitForExistence(timeout: 3))
    }

    func testCompletingATaskOffersToRecordTheResult() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        // Randomized phone number: this test mutates state (completing a task
        // returns 409 on retry, and swiping an already-completed row — which
        // has no swipe action to reveal — can register as a plain tap and
        // navigate into TaskDetailView instead). A brand-new account every
        // run guarantees every seeded task starts open, sidestepping both
        // failure modes instead of working around a shared, mutating account.
        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }

        completePregnancySetup(in: app)

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 15))
        timelineTab.tap()

        // .swipeActions(edge: .leading) 的「完成」按钮靠向右滑手势展开
        // （手指从左往右拖动内容，露出贴在左侧的 leading 按钮），不是 swipeLeft。
        let taskRow = app.buttons.matching(identifier: "timeline-task-row").firstMatch
        XCTAssertTrue(taskRow.waitForExistence(timeout: 8))
        taskRow.swipeRight()

        let completeAction = app.buttons["完成"]
        XCTAssertTrue(completeAction.waitForExistence(timeout: 3))
        completeAction.tap()

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

    /// 焦点卡承载的是「现在最重要」那条任务，而该任务会被 entries(in:) 从
    /// 列表里排除，所以卡片上的按钮是它唯一的入口。按钮写着「开始处理」，
    /// 就必须通向能真正处理它的事项详情，而不是只带一句摘要的 Agent 对话。
    func testFocusCardActionOpensTaskDetailRatherThanAgent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        // 全新账号保证焦点任务处于未完成状态，焦点卡一定会渲染。
        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }

        completePregnancySetup(in: app)

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 15))
        timelineTab.tap()

        // 保存孕期信息会触发整条时间线重新拉取（多次网络往返），
        // 先等周分组头落地，再找焦点卡，否则会在加载态上误判。
        let anyWeekHeader = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'timeline-week-header-'"))
            .firstMatch
        XCTAssertTrue(anyWeekHeader.waitForExistence(timeout: 15))

        // List 懒加载，离屏的行不在无障碍树里，需要滚动到可见范围。
        let action = app.buttons["开始处理"]
        reveal(action, in: app)
        action.tap()

        XCTAssertTrue(
            app.navigationBars["事项详情"].waitForExistence(timeout: 5),
            "「开始处理」应打开事项详情"
        )
        XCTAssertFalse(
            app.navigationBars["AIM"].exists,
            "「开始处理」不应打开 Agent 对话"
        )
    }








    /// 「吃什么」是两个场景：菜谱回答做什么，饮食提示回答注意什么。
    /// 此前混在一个列表里，找菜要在禁忌里翻，查能不能吃要在菜谱里翻。
    func testNutritionSeparatesRecipesFromAdvice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }

        completePregnancySetup(in: app)

        let libraryTab = app.tabBars.buttons["资料库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 15))
        libraryTab.tap()

        let nutrition = app.buttons["library-card-nutrition"]
        reveal(nutrition, in: app)
        nutrition.tap()

        let picker = app.segmentedControls["nutrition-section-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))

        // 默认落在菜谱页：这是「吃什么」最常被记录的东西。
        let addManually = app.buttons["library-add-manually"]
        XCTAssertTrue(addManually.waitForExistence(timeout: 5))
        addManually.tap()

        let title = app.textFields["knowledge-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        title.tap()
        title.typeText("菠菜猪肝汤")

        let ingredient = app.textFields["knowledge-ingredient-0"]
        reveal(ingredient, in: app)
        ingredient.tap()
        ingredient.typeText("菠菜 200g")

        let step = app.textFields["knowledge-step-0"]
        reveal(step, in: app)
        step.tap()
        step.typeText("焯水后煮 3 分钟")

        // 用途是以后找到这道菜的入口。
        let purpose = app.textFields["knowledge-purpose-0"]
        reveal(purpose, in: app)
        purpose.tap()
        purpose.typeText("补铁")

        let save = app.buttons["knowledge-save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(
            app.staticTexts["菠菜猪肝汤"].waitForExistence(timeout: 15),
            "菜谱应出现在菜谱页"
        )
        XCTAssertTrue(
            app.buttons["nutrition-purpose-补铁"].waitForExistence(timeout: 10),
            "用途标签应当来自菜谱自己"
        )

        // 切到饮食提示，菜谱不该出现在这边。
        picker.buttons["饮食提示"].tap()
        XCTAssertFalse(
            app.staticTexts["菠菜猪肝汤"].waitForExistence(timeout: 3),
            "菜谱不该出现在饮食提示里"
        )
    }

    /// Aim 自带的条目此前只有标题和一行摘要、且不可点，用户看到的是一堆
    /// 读不下去的行。这条用例守住「能点进去看完整内容」。
    func testBuiltInReferenceItemsOpenTheirDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }

        completePregnancySetup(in: app)

        let libraryTab = app.tabBars.buttons["资料库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 15))
        libraryTab.tap()

        let nutrition = app.buttons["library-card-nutrition"]
        reveal(nutrition, in: app)
        nutrition.tap()

        // 自带参考归在「饮食提示」下——它们讲的是注意什么，不是菜谱。
        let picker = app.segmentedControls["nutrition-section-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "「吃什么」应当分成菜谱与饮食提示")
        picker.buttons["饮食提示"].tap()

        // 内容 id 来自 content/nutrition，不是写死在客户端的。
        let item = app.buttons["content-item-raw-and-undercooked"]
        reveal(item, in: app)
        item.tap()

        XCTAssertTrue(
            app.navigationBars["生食与未煮熟的食物"].waitForExistence(timeout: 10),
            "自带条目应当能点进详情"
        )
        XCTAssertTrue(
            app.buttons["content-ask-agent"].waitForExistence(timeout: 5),
            "详情里应当能就这条问 AIM"
        )
    }

    /// 「想问医生」此前缺了最关键的一步：产检那天怎么把攒下的问题一次带走。
    /// 这条用例守住完整闭环——攒问题、生成清单、问完一次性标记。
    func testConsultationListClosesTheQuestionLoop() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }

        completePregnancySetup(in: app)

        let libraryTab = app.tabBars.buttons["资料库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 15))
        libraryTab.tap()

        let questions = app.buttons["library-card-questions"]
        reveal(questions, in: app)
        questions.tap()

        // 攒两个问题。清单入口只在有未答问题时才出现。
        let field = app.textFields["library-question-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        for text in ["能不能继续游泳", "这个胎动正常吗"] {
            field.tap()
            field.typeText(text)
            app.buttons["library-question-add"].tap()
            XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 10))
        }

        let consultation = app.buttons["library-consultation-list"]
        reveal(consultation, in: app)
        consultation.tap()

        XCTAssertTrue(
            app.buttons["consultation-mark-all"].waitForExistence(timeout: 10),
            "问诊清单应当能打开"
        )
        XCTAssertTrue(app.staticTexts["能不能继续游泳"].exists, "清单里应当有攒下的问题")

        app.buttons["consultation-mark-all"].tap()

        // 全部标记为已问之后，清单入口应当消失——没有待问的问题了。
        XCTAssertTrue(
            app.buttons["library-question-field"].waitForExistence(timeout: 15)
                || app.textFields["library-question-field"].waitForExistence(timeout: 5),
            "应当回到问题列表"
        )
        XCTAssertFalse(
            app.buttons["library-consultation-list"].waitForExistence(timeout: 5),
            "都问过之后不该还提示生成清单"
        )
    }

    /// 资料库是积累下来的内容，你和 AIM 都能往里加。此前只有 AIM 能加，
    /// 用户想手动录一道菜谱做不到——这条用例守住「自己记一条」这条路径。
    func testUserCanAddAndEditAKnowledgeEntryThemselves() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }

        completePregnancySetup(in: app)

        let libraryTab = app.tabBars.buttons["资料库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 15))
        libraryTab.tap()

        let nutrition = app.buttons["library-card-nutrition"]
        reveal(nutrition, in: app)
        nutrition.tap()

        let addManually = app.buttons["library-add-manually"]
        XCTAssertTrue(addManually.waitForExistence(timeout: 10), "应当能自己记一条")
        addManually.tap()

        XCTAssertTrue(app.navigationBars["新增资料"].waitForExistence(timeout: 8), "录入界面应当弹出")
        let title = app.textFields["knowledge-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("红枣枸杞粥")

        // 吃什么默认按菜谱录，食材与做法都要填齐才能保存。
        let ingredient = app.textFields["knowledge-ingredient-0"]
        reveal(ingredient, in: app)
        ingredient.tap()
        ingredient.typeText("红枣 5 颗")

        let step = app.textFields["knowledge-step-0"]
        reveal(step, in: app)
        step.tap()
        step.typeText("洗净后煮 30 分钟")

        let save = app.buttons["knowledge-save"]
        XCTAssertTrue(save.isEnabled, "填齐后应当可以保存")
        save.tap()

        XCTAssertTrue(
            app.staticTexts["红枣枸杞粥"].waitForExistence(timeout: 15),
            "自己记的条目应出现在分类里"
        )
    }

    /// 产检指标是趋势图与「本周关注」血压规则的数据源。此前后端支持
    /// metrics 字段，但界面上填不了——这条用例守住录入链路。
    func testCheckupMetricsCanBeRecorded() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }

        completePregnancySetup(in: app)

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 15))
        timelineTab.tap()

        let addRecord = app.buttons["新增记录"]
        XCTAssertTrue(addRecord.waitForExistence(timeout: 10))
        addRecord.tap()

        app.buttons["record-type-checkup"].tap()

        // 按序号定位文本框会踩焦点竞态，用稳定标识。
        for (identifier, value) in [
            ("checkup-hospital", "市一医院"),
            ("checkup-exam-items", "常规产检"),
            ("checkup-result", "正常"),
            ("checkup-advice", "按时复查"),
        ] {
            let field = app.textFields[identifier]
            reveal(field, in: app)
            field.tap()
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.typeText(value)
        }

        let weight = app.textFields["checkup-metric-weight"]
        reveal(weight, in: app)
        weight.tap()
        weight.typeText("62.5")

        let systolic = app.textFields["checkup-metric-systolic"]
        systolic.tap()
        systolic.typeText("118")

        let save = app.buttons["保存记录"]
        reveal(save, in: app)
        save.tap()

        // 存下去之后资料库的产检卡应当反映出这条记录。
        let libraryTab = app.tabBars.buttons["资料库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 15))
        libraryTab.tap()

        let checkups = app.buttons["library-card-checkups"]
        XCTAssertTrue(checkups.waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.staticTexts["1 次记录"].waitForExistence(timeout: 10),
            "录入的产检应出现在资料库"
        )
    }

    /// 想问医生与待产准备走的是同一套机制：内容库出条目，checklist 记录存勾选状态。
    /// 这条用例验证两者都能真的写进去，而不只是渲染出来。
    func testLibraryQuestionsAndChecklistCanBeWrittenTo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }

        completePregnancySetup(in: app)

        let libraryTab = app.tabBars.buttons["资料库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 15))
        libraryTab.tap()

        let questions = app.buttons["library-card-questions"]
        reveal(questions, in: app)
        questions.tap()

        let field = app.textFields["library-question-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("能不能继续游泳")
        app.buttons["library-question-add"].tap()

        XCTAssertTrue(
            app.staticTexts["能不能继续游泳"].waitForExistence(timeout: 10),
            "新增的问题应出现在列表里"
        )

        app.navigationBars.buttons.firstMatch.tap()

        let preparation = app.buttons["library-card-preparation"]
        reveal(preparation, in: app)
        preparation.tap()

        // 待产包条目来自 content/preparation，不是写死在客户端的。
        let documents = app.buttons["library-checklist-documents"]
        XCTAssertTrue(documents.waitForExistence(timeout: 10), "清单条目应来自内容库")
        documents.tap()

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.buttons["library-card-preparation"].waitForExistence(timeout: 10),
            "返回后卡片应仍在"
        )
    }

    /// 资料库把此前散落或看不见的孕期信息收到一处。危险信号的内容早就在
    /// content/safety-rules 里，但在这个 Tab 之前 App 里没有任何入口。
    func testLibraryTabShowsCategoryCardsAndOpensSafetyRules() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }

        completePregnancySetup(in: app)

        let libraryTab = app.tabBars.buttons["资料库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 15))
        libraryTab.tap()

        // 分类卡来自 LibraryCatalog，不是写死在视图里的。
        XCTAssertTrue(app.buttons["library-card-symptoms"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["library-card-checkups"].exists)

        let safety = app.buttons["library-card-safety"]
        reveal(safety, in: app)
        safety.tap()

        XCTAssertTrue(
            app.otherElements["library-safety-list"].waitForExistence(timeout: 10)
                || app.tables["library-safety-list"].waitForExistence(timeout: 2)
                || app.collectionViews["library-safety-list"].waitForExistence(timeout: 2),
            "危险信号应能打开并列出内容"
        )
    }

    /// 登录后没有孕期档案时，日期录入必须是一道准入门槛：自动出现、不能跳过、
    /// 且不预先替用户填一个日期。原实现是可忽略的空状态按钮 + 预填「今天 + 154 天」，
    /// 结果是用户不填也能用，或者不看就提交了一个假预产期。
    func testPregnancySetupGatesEntryAndRequiresAnExplicitDate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }

        // 不点任何东西，录入界面就应该自己出现，且底部 Tab 还进不去。
        let save = app.buttons["pregnancy-setup-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "登录后应直接进入孕期信息录入")
        XCTAssertFalse(app.tabBars.buttons["孕期"].exists, "填完之前不应能进入主界面")

        // 没选日期 → 不能保存。
        XCTAssertFalse(save.isEnabled, "未选择日期时不应允许保存")

        let choose = app.buttons["pregnancy-setup-choose-date"]
        XCTAssertTrue(choose.waitForExistence(timeout: 3))
        choose.tap()

        // 展开选择器本身不算数——必须真的拨动滚轮。
        let wheel = app.pickerWheels.element(boundBy: 0)
        XCTAssertTrue(wheel.waitForExistence(timeout: 3))
        XCTAssertFalse(save.isEnabled, "仅展开选择器不应视为已选择")

        wheel.swipeUp()

        XCTAssertTrue(save.isEnabled, "拨动日期后应允许保存")
        save.tap()

        XCTAssertTrue(
            app.tabBars.buttons["孕期"].waitForExistence(timeout: 15),
            "保存后应进入主界面"
        )
    }

    /// 登录后没有孕期档案时，日期录入是一道准入门槛。日期不再预填，
    /// 必须真的拨动滚轮才算选定——所以这里不能只是「点保存」。



    /// 办事指南和待产准备走的是 checklist(collection:) 那条分支，它只渲染静态
    /// 内容集合，从不渲染用户和 AIM 攒下来的条目。于是「自己记一条」和
    /// 「让 AIM 记」两个入口都在，条目也确实存进了服务端，但详情页什么都不显示。
    func testPaperworkShowsEntriesAddedByHand() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
            app.buttons["开始体验"].tap()
        }
        completePregnancySetup(in: app)

        let libraryTab = app.tabBars.buttons["资料库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 15))
        libraryTab.tap()

        let paperwork = app.buttons["library-card-paperwork"]
        reveal(paperwork, in: app)
        paperwork.tap()

        let addManually = app.buttons["library-add-manually"]
        XCTAssertTrue(addManually.waitForExistence(timeout: 10), "办事指南应当能自己记一条")
        addManually.tap()

        XCTAssertTrue(app.navigationBars["新增资料"].waitForExistence(timeout: 8))
        let title = app.textFields["knowledge-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("建卡当天的流程")

        // 办事指南默认按「提示」录，只需要正文。
        let body = app.textFields["knowledge-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5), "提示形态应当有正文输入框")
        reveal(body, in: app)
        body.tap()
        body.typeText("先取号再建档，社保卡和身份证都要带")

        let save = app.buttons["knowledge-save"]
        reveal(save, in: app)
        XCTAssertTrue(save.isEnabled, "填齐后应当可以保存")
        save.tap()

        XCTAssertTrue(
            app.staticTexts["建卡当天的流程"].waitForExistence(timeout: 15),
            "存进去的条目必须出现在办事指南里，否则等于存进了看不见的地方"
        )
    }

    private func completePregnancySetup(in app: XCUIApplication) {
        let save = app.buttons["pregnancy-setup-save"]
        guard save.waitForExistence(timeout: 10) else { return }

        app.buttons["pregnancy-setup-choose-date"].tap()
        XCTAssertTrue(app.pickerWheels.element(boundBy: 0).waitForExistence(timeout: 3))

        // 拨到「今天 + 154 天」= 孕 18 周。content/ 里只有 5–12 周和 18–19 周
        // 有任务，随便拨一个日期会得到空计划，后续断言就无从谈起。
        // 这个日期是测试显式选的，不是 App 替用户预填的——正是本次改动的分界。
        // 滚轮是 [月(英文全称), 日, 年] 三列 —— 由 XCUITest 的报错反馈确定，
        // 不是猜的。月份用英文是选择器自身的呈现，与 App 的中文界面无关。
        let target = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: 154, to: Date())!
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let parts = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day], from: target)
        formatter.dateFormat = "MMMM"
        // 顺序必须是 年 → 月 → 日。选择器范围下界是今天，先拨月份会让日期
        // 暂时落到范围外被夹回去，年份就再也拨不对了。
        let adjustments: [(index: Int, value: String)] = [
            (2, "\(parts.year!)"),
            (0, formatter.string(from: target)),
            (1, "\(parts.day!)"),
        ]
        for adjustment in adjustments {
            let wheel = app.pickerWheels.element(boundBy: adjustment.index)
            if wheel.exists { wheel.adjust(toPickerWheelValue: adjustment.value) }
        }

        XCTAssertTrue(save.isEnabled, "选定日期后应允许保存")
        save.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if element.waitForExistence(timeout: 1) { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, "Expected \(element) to be reachable")
    }
}
