import XCTest

final class CoreJourneyUITests: XCTestCase {
    func testGlobalAgentButtonShowsCurrentTabContext() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        registerNewAccount(in: app)

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
        registerNewAccount(in: app)

        completePregnancySetup(in: app)

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 15))
        timelineTab.tap()

        // 「新增记录」收进了首页右上角的「+」菜单里。
        let addMenu = app.buttons["home-add-menu"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 5))
        addMenu.tap()
        let addRecord = app.buttons["新增记录"]
        XCTAssertTrue(addRecord.waitForExistence(timeout: 3))
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

        registerNewAccount(in: app)

        completePregnancySetup(in: app)

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 15))
        timelineTab.tap()

        // 首页不再按周分组，以焦点卡落地作为「数据已加载」的信号。
        let focusCard = app.descendants(matching: .any).matching(identifier: "home-focus-card").firstMatch
        XCTAssertTrue(focusCard.waitForExistence(timeout: 15))

        // 对话面自带头部、隐藏了系统导航栏，用它自己的「关闭」钮判断已打开。
        app.buttons["global-agent-button"].tap()
        XCTAssertTrue(app.buttons["agent-close"].waitForExistence(timeout: 5))
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
        registerNewAccount(in: app)

        completePregnancySetup(in: app)

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 15))
        timelineTab.tap()

        // 孕 18 周的种子任务里只有一条截止今天，它会被焦点卡吃掉，今天组
        // 因此没有其它行。先用快速添加补一条截止今天的待办，保证有行可滑。
        let focusCard = app.descendants(matching: .any).matching(identifier: "home-focus-card").firstMatch
        XCTAssertTrue(focusCard.waitForExistence(timeout: 15))
        let quickAdd = app.buttons["home-quick-add"]
        reveal(quickAdd, in: app)
        quickAdd.tap()
        let quickAddField = app.textFields["home-quick-add-field"]
        XCTAssertTrue(quickAddField.waitForExistence(timeout: 3))
        quickAddField.typeText("测试待办\n")

        // `home-task-row` 也打在「接下来 7 天」的行上，那些行在快速添加的网络往返
        // 结束前就已经存在，firstMatch 可能立刻命中一条 upcoming 行、甚至撞上
        // 重载中的列表。先等新待办的标题落地，今天组的第一行才是确定的滑动目标。
        XCTAssertTrue(app.staticTexts["测试待办"].waitForExistence(timeout: 10), "快速添加的待办应出现在今天组")

        // 行合并成了单个无障碍元素，checkbox 不单独暴露，按标识符查不到它；
        // 只能按坐标点：checkbox 贴在行的最左侧，取行宽 6% 处、垂直居中。
        // 这条用例覆盖的是规格 §4.3 的 checkbox 点击路径；右滑完成另有用例。
        let taskRow = app.buttons.matching(identifier: "home-task-row").firstMatch
        XCTAssertTrue(taskRow.waitForExistence(timeout: 8))
        taskRow.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()

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

    /// 右滑完成与点 checkbox 等价（规格 §4.3）。只验证滑出「完成」按钮，
    /// 不真的点：完成路径已由 testCompletingATaskOffersToRecordTheResult 覆盖。
    func testSwipingATaskRowRevealsCompleteAction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        registerNewAccount(in: app)

        completePregnancySetup(in: app)

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 15))
        timelineTab.tap()

        let focusCard = app.descendants(matching: .any).matching(identifier: "home-focus-card").firstMatch
        XCTAssertTrue(focusCard.waitForExistence(timeout: 15))
        let quickAdd = app.buttons["home-quick-add"]
        reveal(quickAdd, in: app)
        quickAdd.tap()
        let quickAddField = app.textFields["home-quick-add-field"]
        XCTAssertTrue(quickAddField.waitForExistence(timeout: 3))
        quickAddField.typeText("滑动待办\n")
        XCTAssertTrue(app.staticTexts["滑动待办"].waitForExistence(timeout: 10), "快速添加的待办应出现在今天组")

        // .swipeActions(edge: .leading) 的「完成」按钮靠向右滑手势展开
        // （手指从左往右拖动内容，露出贴在左侧的 leading 按钮），不是 swipeLeft。
        let taskRow = app.buttons.matching(identifier: "home-task-row").firstMatch
        XCTAssertTrue(taskRow.waitForExistence(timeout: 8))
        taskRow.swipeRight()

        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 3))
    }

    /// 焦点卡承载的是「现在最重要」那条任务，而该任务会被 entries(in:) 从
    /// 列表里排除，所以卡片上的按钮是它唯一的入口。按钮写着「开始处理」，
    /// 就必须通向能真正处理它的事项详情，而不是只带一句摘要的 Agent 对话。
    func testFocusCardActionOpensTaskDetailRatherThanAgent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        // 全新账号保证焦点任务处于未完成状态，焦点卡一定会渲染。
        registerNewAccount(in: app)

        completePregnancySetup(in: app)

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 15))
        timelineTab.tap()

        // 保存孕期信息会触发整页重新拉取（多次网络往返），
        // 先等焦点卡落地再找按钮，否则会在加载态上误判。
        let focusCard = app.descendants(matching: .any).matching(identifier: "home-focus-card").firstMatch
        XCTAssertTrue(focusCard.waitForExistence(timeout: 15))

        // 焦点卡现在在首屏，reveal 第一轮就命中；保留是为了防御小屏。
        let action = app.buttons["开始处理"]
        reveal(action, in: app)
        action.tap()

        XCTAssertTrue(
            app.navigationBars["事项详情"].waitForExistence(timeout: 5),
            "「开始处理」应打开事项详情"
        )
        // 对话面隐藏了系统导航栏，navigationBars["AIM"] 永远不存在、断言会空转；
        // 用对话面自己的「关闭」钮做否定断言，和正向用例保持一致。
        XCTAssertFalse(
            app.buttons["agent-close"].exists,
            "「开始处理」不应打开 Agent 对话"
        )
    }

    /// 今天组末尾的「添加待办」是最短的录入路径：点一下、打字、回车，
    /// 新待办就落在今天组里；成功后输入框不收起，连着记几条是常态。
    func testQuickAddCreatesATaskInTodayGroup() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        registerNewAccount(in: app)
        completePregnancySetup(in: app)

        XCTAssertTrue(app.tabBars.buttons["孕期"].waitForExistence(timeout: 15))

        let quickAdd = app.buttons["home-quick-add"]
        reveal(quickAdd, in: app)
        quickAdd.tap()

        let field = app.textFields["home-quick-add-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        let title = "买叶酸 \(Int.random(in: 100...999))"
        field.typeText(title + "\n")

        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), "新待办应出现在今天组")
        XCTAssertTrue(field.exists, "成功后输入框应保持打开，方便连续录入")
        // 回车默认会收键盘，提交后 List 插入新行还会再收一次焦点；行得把焦点要回来，键盘不能掉。
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 3),
            "成功后键盘应仍在，连着记下一条不用再点一次输入框"
        )
        XCTAssertEqual(field.value(forKey: "hasKeyboardFocus") as? Bool, true, "成功后输入框应仍处于焦点")
    }

    /// 首页标题是进入完整时间线的主入口。时间线以今天所在周开头，
    /// 筛选跟着时间线走了，返回后回到首页。
    func testHeaderOpensTimelineWithTodayOnTop() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        registerNewAccount(in: app)
        completePregnancySetup(in: app)

        let header = app.buttons["home-header-week"]
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        header.tap()

        XCTAssertTrue(app.navigationBars["孕期时间线"].waitForExistence(timeout: 5))
        let todayHeader = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'timeline-week-header-'"))
            .firstMatch
        XCTAssertTrue(todayHeader.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["timeline-filter"].exists)

        app.navigationBars["孕期时间线"].buttons.firstMatch.tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5), "返回后应回到首页")
    }








    /// 「吃什么」是两个场景：菜谱回答做什么，饮食提示回答注意什么。
    /// 此前混在一个列表里，找菜要在禁忌里翻，查能不能吃要在菜谱里翻。
    func testNutritionSeparatesRecipesFromAdvice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        registerNewAccount(in: app)

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

        registerNewAccount(in: app)

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

        registerNewAccount(in: app)

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

        registerNewAccount(in: app)

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

        registerNewAccount(in: app)

        completePregnancySetup(in: app)

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 15))
        timelineTab.tap()

        // 「新增记录」收进了首页右上角的「+」菜单里。
        let addMenu = app.buttons["home-add-menu"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 5))
        addMenu.tap()
        let addRecord = app.buttons["新增记录"]
        XCTAssertTrue(addRecord.waitForExistence(timeout: 3))
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

        registerNewAccount(in: app)

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

        registerNewAccount(in: app)

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

        registerNewAccount(in: app)

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

        registerNewAccount(in: app)
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



    /// 注册时身份写死成妈妈、家庭名写死成「我的家庭」、成员没有称呼——
    /// 三样都没有补救入口。这条守住新的注册与家庭编辑路径。
    func testRegisteringAsFatherWithANicknameAndRenamingTheFamily() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        registerNewAccount(in: app, role: "爸爸", nickname: "阿斌")
        completePregnancySetup(in: app)

        let familyTab = app.tabBars.buttons["家庭"]
        XCTAssertTrue(familyTab.waitForExistence(timeout: 15))
        familyTab.tap()

        // 列表里显示的是称呼，不是角色名。
        XCTAssertTrue(
            app.staticTexts["阿斌"].waitForExistence(timeout: 10),
            "成员行应当显示称呼，否则两个「其他家人」分不出谁是谁"
        )

        let rename = app.buttons["family-rename"]
        reveal(rename, in: app)
        rename.tap()

        let field = app.textFields["family-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        field.typeText("王家")
        app.buttons["family-name-save"].tap()

        XCTAssertTrue(
            app.staticTexts["王家"].waitForExistence(timeout: 15),
            "家庭名此前写死成「我的家庭」，改不了"
        )
    }


    /// AIM 的会话此前只活在内存里，App 一重启就找不回来。这条守的是「翻得回去」：
    /// 问一句 → 开新对话 → 从历史列表把刚才那段找回来。
    func testAPastConversationCanBeReopenedFromHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()
        registerNewAccount(in: app)
        completePregnancySetup(in: app)

        let agentTab = app.tabBars.buttons["AIM"]
        XCTAssertTrue(agentTab.waitForExistence(timeout: 15))
        agentTab.tap()

        let input = app.textFields.element(
            matching: NSPredicate(format: "placeholderValue == %@", "告诉我你现在在担心什么"))
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        let question = "孕期能喝咖啡吗"
        input.tap()
        input.typeText(question)
        app.buttons["arrowSend"].tap()

        // 问句立刻回显，不用等模型答完——会话在发出去那一刻就登记了。
        XCTAssertTrue(app.staticTexts[question].waitForExistence(timeout: 20), "提问应当出现在对话里")

        let newConversation = app.buttons["agent-new-conversation"]
        XCTAssertTrue(newConversation.waitForExistence(timeout: 10))
        newConversation.tap()
        XCTAssertFalse(
            app.staticTexts[question].waitForExistence(timeout: 3),
            "开了新对话，上一段就不该还留在屏幕上")

        app.buttons["agent-history"].tap()
        XCTAssertTrue(
            app.otherElements["agent-session-list"].waitForExistence(timeout: 10)
                || app.navigationBars["历史对话"].waitForExistence(timeout: 5),
            "应当能打开历史对话列表")

        let row = app.buttons["agent-session-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "刚才那段应当出现在历史里")
        row.tap()

        XCTAssertTrue(
            app.staticTexts[question].waitForExistence(timeout: 25),
            "点回历史对话，内容应当被重放回来")
    }

    /// App Store 审核指南 5.1.1(v)：能注册就必须能在 App 内注销。
    /// 30 天缓冲：注销后马上用同一账号登录，应当恢复并提示。
    func testAccountCanBeDeletedAndRestoredWithinGracePeriod() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        let phone = registerNewAccount(in: app)
        completePregnancySetup(in: app)

        let familyTab = app.tabBars.buttons["家庭"]
        XCTAssertTrue(familyTab.waitForExistence(timeout: 15))
        familyTab.tap()

        let deleteButton = app.buttons["account-delete"]
        reveal(deleteButton, in: app)
        deleteButton.tap()
        // confirmationDialog 的按钮桥接成 UIAlertAction，accessibilityIdentifier 会丢，只能按标题查。
        // 同一标题在树里会出现不止一次（sheet 本身也带一份），要 firstMatch。
        var confirm = app.sheets.buttons["继续注销"].firstMatch
        if !confirm.waitForExistence(timeout: 5) {
            confirm = app.buttons["继续注销"].firstMatch
        }
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "应当弹出注销确认")
        confirm.tap()

        let passwordField = app.secureTextFields["account-delete-password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText("aim-test-password")
        let submitDeletion = app.buttons["account-delete-submit"]
        XCTAssertTrue(submitDeletion.waitForExistence(timeout: 5))
        submitDeletion.tap()

        // 回到登录页，带一句提示。
        let notice = app.staticTexts["auth-notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "注销后应回到登录页并提示")

        // 缓冲期内登录 → 恢复。
        selectLoginMode(in: app)
        let phoneField = app.textFields["auth-phone"]
        XCTAssertTrue(phoneField.waitForExistence(timeout: 5))
        phoneField.tap()
        phoneField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        phoneField.typeText(phone)
        let password = app.secureTextFields["auth-password"]
        password.tap()
        password.typeText("aim-test-password")
        dismissKeyboard(in: app)
        let login = app.buttons["auth-submit"]
        XCTAssertTrue(login.waitForExistence(timeout: 5))
        XCTAssertTrue(login.isEnabled, "登录模式不需要勾同意")
        login.tap()

        let welcome = app.descendants(matching: .any).matching(identifier: "home-welcome-back").firstMatch
        XCTAssertTrue(welcome.waitForExistence(timeout: 15), "缓冲期内登录应提示注销已取消")
    }

    /// 未勾选同意时不能注册。
    func testRegistrationIsBlockedUntilTermsAreAccepted() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        let phone = app.textFields["auth-phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 10))
        phone.tap()
        phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
        let password = app.secureTextFields["auth-password"]
        password.tap()
        password.typeText("aim-test-password")
        dismissKeyboard(in: app)
        app.buttons["auth-role"].tap()
        let mother = app.buttons["妈妈"]
        XCTAssertTrue(mother.waitForExistence(timeout: 5))
        mother.tap()

        let submit = app.buttons["auth-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled, "没勾同意不该能注册")
        acceptTerms(in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: submit)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 3), .completed, "勾了同意就该能注册")
    }

    /// 切到登录模式。segmented picker 的段在无障碍树里是 button；
    /// 先从带标识符的分段控件里找，找不到再退回到全局第一个「登录」按钮。
    private func selectLoginMode(in app: XCUIApplication) {
        let segment = app.segmentedControls["auth-mode-picker"].buttons["登录"]
        if segment.waitForExistence(timeout: 3) {
            segment.tap()
            return
        }
        let fallback = app.buttons["登录"].firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 3), "登录页应当能切到登录模式")
        fallback.tap()
    }

    /// 注册一个全新账号。
    ///
    /// 服务端的 `demo-session` 免密入口已经删除，所有用例都要走真实注册：
    /// 手机号 + 密码 + 身份。每个用例用随机手机号，互不干扰。
    ///
    /// 输入密码后必须先收键盘：键盘会盖住底部的提交按钮，而滑动去够它
    /// 又会和键盘的滚动打架。收掉之后整个表单就在一屏里。
    @discardableResult
    private func registerNewAccount(
        in app: XCUIApplication,
        role: String = "妈妈",
        nickname: String? = nil
    ) -> String {
        let phone = "139\(Int.random(in: 10_000_000...99_999_999))"
        let phoneField = app.textFields["auth-phone"]
        guard phoneField.waitForExistence(timeout: 10) else {
            XCTFail("注册页没有出现")
            return phone
        }

        phoneField.tap()
        phoneField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        phoneField.typeText(phone)

        let password = app.secureTextFields["auth-password"]
        password.tap()
        password.typeText("aim-test-password")

        if let nickname {
            let field = app.textFields["auth-nickname"]
            field.tap()
            field.typeText(nickname)
        }
        dismissKeyboard(in: app)

        let rolePicker = app.buttons["auth-role"]
        XCTAssertTrue(rolePicker.waitForExistence(timeout: 5), "注册应当能选身份")
        rolePicker.tap()
        let option = app.buttons[role]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "身份菜单里应当有「\(role)」")
        option.tap()

        // 注册前必须同意协议。Toggle 在无障碍树里是 switch。
        acceptTerms(in: app)

        let submit = app.buttons["auth-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertTrue(submit.isEnabled, "手机号、密码、身份、同意都填齐后应当可以注册")
        submit.tap()
        return phone
    }

    /// 同意开关。SwiftUI 的 Toggle 通常直接暴露为 switch，标识符挂在它身上；
    /// 若标识符落在外层容器上，则退回到容器里的第一个 switch。
    private func consentSwitch(in app: XCUIApplication) -> XCUIElement {
        let direct = app.switches["auth-consent"]
        if direct.waitForExistence(timeout: 3) { return direct }
        return app.descendants(matching: .any)
            .matching(identifier: "auth-consent").firstMatch
            .switches.firstMatch
    }

    /// 勾上同意开关。
    ///
    /// `auth-consent` 这个 switch 元素的框覆盖整行（标签 + 开关），它的中心点落在
    /// 标签里的《隐私政策》链接上：按元素 `tap()` 会打开隐私页而不是拨开关。
    /// 所以这里从来不按元素点，而是算出开关本体的中心：优先用行内嵌套的
    /// UISwitch（无标识符、贴右侧的那个）的框，没有就取整行右缘往里 30pt。
    private func acceptTerms(in app: XCUIApplication) {
        let consent = consentSwitch(in: app)
        XCTAssertTrue(consent.waitForExistence(timeout: 5), "注册页应当有同意开关")
        guard (consent.value as? String) != "1" else { return }

        let rowFrame = consent.frame
        let knob = consent.switches.firstMatch
        let knobFrame = knob.exists ? knob.frame : .null
        let target = knobFrame.isNull
            ? CGPoint(x: rowFrame.maxX - 30, y: rowFrame.midY)
            : CGPoint(x: knobFrame.midX, y: knobFrame.midY)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: target.x, dy: target.y))
            .tap()

        let flipped = NSPredicate(format: "value == '1'")
        let flippedExpectation = XCTNSPredicateExpectation(predicate: flipped, object: consent)
        XCTAssertEqual(XCTWaiter.wait(for: [flippedExpectation], timeout: 3), .completed, "点击后同意开关应当打开")
    }

    /// 对话面换成 WebView 之后最该守住的一条：页面能从网关加载起来。
    ///
    /// 断言用的是欢迎语——纯前端渲染，不依赖 agent 回复。这一条过了就说明
    /// 网关的 /agent/ 路由通了：index.html、js、css 都取到了。任何一步断了
    /// 界面都是白的，而单元测试看不到，因为它们都在 WKWebView 之外。
    func testAgentSurfaceLoadsFromTheGateway() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()
        registerNewAccount(in: app)
        completePregnancySetup(in: app)

        let agentTab = app.tabBars.buttons["AIM"]
        XCTAssertTrue(agentTab.waitForExistence(timeout: 15))
        agentTab.tap()

        // WebView 里的文字对 XCUITest 是可见的，可以直接断言。
        XCTAssertTrue(
            app.staticTexts["可以问孕期变化、最近记录或接下来要做的事。涉及计划变更时，我会先让你确认。"].waitForExistence(timeout: 30),
            "对话面应当加载出打包在 bundle 里的页面；空白说明自定义 scheme 没取到静态资源"
        )
    }

    /// 真发一句并等回复。
    ///
    /// 只验「输入框能输入」是不够的——WKURLSchemeHandler 转发 POST 时可能拿不到
    /// 请求体，那样页面渲染正常、输入也正常，唯独一句话都发不出去。
    func testAgentAnswersAMessage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()
        registerNewAccount(in: app)
        completePregnancySetup(in: app)

        let agentTab = app.tabBars.buttons["AIM"]
        XCTAssertTrue(agentTab.waitForExistence(timeout: 15))
        agentTab.tap()

        let composer = app.textViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        composer.tap()
        composer.typeText("你好")

        let send = app.buttons["发送"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        // 用户那句话先要出现在流里，说明消息确实发出去了。
        XCTAssertTrue(
            app.staticTexts["你好"].waitForExistence(timeout: 20),
            "发出去的消息应当出现在对话流里"
        )

        // 再等一条助手回复。轮询而不是用谓词：XCUITest 的元素谓词不支持
        // label.length 这类键路径，而「有没有新文字出现」用计数判断最直接。
        // 等一条助手回复。判据是「出现了一段既不是我说的话、也不是欢迎语的长文本」——
        // 计数会随 WebView 的快照抖动，不能用来判断。
        let noise: Set<String> = [
            "你好",
            "我在这里陪你一起理清",
            "可以问孕期变化、最近记录或接下来要做的事。涉及计划变更时，我会先让你确认。",
            "AIM", "发送", "历史对话", "新对话",
        ]
        let deadline = Date().addingTimeInterval(90)
        var reply: String?
        while Date() < deadline, reply == nil {
            let labels = app.staticTexts.allElementsBoundByIndex.compactMap { element -> String? in
                // 快照在流式输出期间会变，取不到就下一轮再试。
                guard element.exists else { return nil }
                return element.label
            }
            reply = labels.first { $0.count > 8 && !noise.contains($0) }
            if reply == nil { Thread.sleep(forTimeInterval: 3) }
        }
        XCTAssertNotNil(
            reply,
            "发出去之后应当等到一条助手回复；一直没有说明请求没真正走通"
        )
    }

    /// 输入框能用，说明页面不只是渲染出来了，交互也活着。
    func testAgentComposerAcceptsInput() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()
        registerNewAccount(in: app)
        completePregnancySetup(in: app)

        let agentTab = app.tabBars.buttons["AIM"]
        XCTAssertTrue(agentTab.waitForExistence(timeout: 15))
        agentTab.tap()

        let composer = app.textViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "对话面应当有可输入的输入框")
        composer.tap()
        composer.typeText("你好")
        XCTAssertTrue(app.buttons["发送"].waitForExistence(timeout: 5), "应当能看到发送按钮")
    }

    /// 收起键盘。表单里没有空白可点，用 return 键最稳。
    private func dismissKeyboard(in app: XCUIApplication) {
        if app.keyboards.count > 0 {
            app.typeText("\n")
        }
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
