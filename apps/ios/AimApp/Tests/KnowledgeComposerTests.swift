import XCTest
@testable import AimApp

@MainActor
final class KnowledgeComposerTests: XCTestCase {
    /// 资料库是积累下来的内容，你和 AIM 都能往里加。
    /// 此前只有 AIM 能加，用户想手动录一道菜谱做不到。
    func testARecipeDraftCarriesIngredientsAndSteps() {
        var model = KnowledgeComposerModel(category: .nutrition)
        model.form = .recipe
        model.title = "红枣枸杞粥"
        model.ingredients = ["红枣 5 颗", "枸杞一小把", "大米 100g"]
        model.steps = ["食材洗净", "一起煮 30 分钟"]

        let draft = model.draft()

        XCTAssertEqual(draft?.type, .knowledge)
        XCTAssertEqual(draft?.title, "红枣枸杞粥")
        guard case let .knowledge(data) = draft?.structuredData else {
            return XCTFail("应当是知识条目")
        }
        XCTAssertEqual(data.ingredients?.count, 3)
        XCTAssertEqual(data.category, "nutrition")
    }

    /// 空行是用户编辑列表时的常态，不该被当成一条食材存进去。
    func testBlankLinesAreDroppedFromLists() {
        var model = KnowledgeComposerModel(category: .nutrition)
        model.form = .recipe
        model.title = "粥"
        model.ingredients = ["大米", "   ", ""]
        model.steps = ["煮"]

        guard case let .knowledge(data) = model.draft()?.structuredData else {
            return XCTFail("应当是知识条目")
        }
        XCTAssertEqual(data.ingredients, ["大米"])
    }

    /// 每种形态要求的字段不同，缺了就不该让存——
    /// 后端也会拒，不如在按钮上就禁掉。
    func testARecipeNeedsBothIngredientsAndSteps() {
        var model = KnowledgeComposerModel(category: .nutrition)
        model.form = .recipe
        model.title = "半成品"
        model.ingredients = ["大米"]

        XCTAssertFalse(model.canSave)
        XCTAssertNil(model.draft())
    }

    func testAFoodRuleNeedsAVerdictAndReason() {
        var model = KnowledgeComposerModel(category: .nutrition)
        model.form = .foodRule
        model.title = "螃蟹"
        model.verdict = .avoid

        XCTAssertFalse(model.canSave, "只有结论没有原因，用户没法判断是否适用于自己")

        model.reason = "性寒，孕期常被建议避免；具体请咨询医生"
        XCTAssertTrue(model.canSave)
    }

    func testATitleIsAlwaysRequired() {
        var model = KnowledgeComposerModel(category: .preparation)
        model.form = .tip
        model.body = "正文"

        XCTAssertFalse(model.canSave)
        model.title = "待产包提醒"
        XCTAssertTrue(model.canSave)
    }

    /// 编辑既有条目时要能把内容读回表单。
    func testEditingLoadsAnExistingEntry() {
        let record = RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .knowledge, occurredAt: .now, visibility: .family,
            title: "菠菜猪肝汤", content: nil,
            structuredData: .knowledge(KnowledgeRecordData(
                category: "nutrition", form: .recipe,
                ingredients: ["菠菜"], steps: ["煮"])),
            attachmentRefs: [], createdAt: .now, updatedAt: .now)
        let entry = KnowledgeEntry(record: record)!

        let model = KnowledgeComposerModel(entry: entry)

        XCTAssertEqual(model.title, "菠菜猪肝汤")
        XCTAssertEqual(model.form, .recipe)
        XCTAssertEqual(model.ingredients, ["菠菜"])
        XCTAssertTrue(model.canSave)
    }

    /// 换形态时不该把已填的标题清掉——用户只是改了呈现方式。
    func testSwitchingFormKeepsTheTitle() {
        var model = KnowledgeComposerModel(category: .nutrition)
        model.title = "螃蟹"
        model.form = .recipe
        model.form = .foodRule

        XCTAssertEqual(model.title, "螃蟹")
    }
}

@MainActor
final class RecordDraftValidationTests: XCTestCase {
    /// 客户端有一份「类型 → 结构」的白名单，漏了就在发请求前被拦掉，
    /// 表现为后端明明支持却存不进去。这个坑已经踩过两次（question/checklist
    /// 一次、knowledge 一次），用测试守住每一种类型。
    func testEveryWritableRecordTypePassesClientValidation() async {
        let cases: [(RecordType, RecordStructuredData)] = [
            (.symptom, .symptom(SymptomRecordData(symptoms: ["恶心"], severity: 2, note: nil))),
            (.checkup, .checkup(CheckupRecordData(
                hospital: "市一", examItems: "常规", result: "正常", doctorAdvice: "复查"))),
            (.note, .note),
            (.question, .question(QuestionRecordData(answered: false, answer: nil))),
            (.checklist, .checklist(ChecklistRecordData(
                collection: "preparation", itemID: "documents", done: true))),
            (.knowledge, .knowledge(KnowledgeRecordData(
                category: "nutrition", form: .tip, body: "正文"))),
        ]

        let repository = BusinessRepository(environment: APIEnvironment(
            baseURL: URL(string: "http://127.0.0.1:1")!,
            eveBaseURL: URL(string: "http://127.0.0.1:1")!,
            bearerToken: "t", accountID: UUID(), familyID: UUID(), pregnancyID: UUID()))

        for (type, data) in cases {
            let draft = RecordDraft(
                type: type, occurredAt: .now, visibility: .family,
                title: "标题", content: "正文", structuredData: data)
            do {
                _ = try await repository.createRecord(draft: draft)
                XCTFail("不该真的连上网络")
            } catch let error as APIError {
                // 通过校验后会去发请求，因而失败在网络层而不是 invalidResponse。
                XCTAssertNotEqual(
                    error, .invalidResponse,
                    "\(type.rawValue) 被客户端白名单拦掉了")
            } catch {
                // URLError 等网络错误说明已经走到发请求那一步，符合预期。
            }
        }
    }
}

@MainActor
final class KnowledgeComposerNutritionTests: XCTestCase {
    func testARecipeCarriesItsPurposes() {
        var model = KnowledgeComposerModel(category: .nutrition)
        model.form = .recipe
        model.title = "菠菜猪肝汤"
        model.ingredients = ["菠菜"]
        model.steps = ["煮"]
        model.purposes = ["补铁", "  "]

        guard case let .knowledge(data) = model.draft()?.structuredData else {
            return XCTFail("应当是知识条目")
        }
        XCTAssertEqual(data.purposes, ["补铁"], "空行不该被当成用途")
    }

    /// 「补铁要配维C」归不进能吃/不能吃任何一档，所以结论可以留空。
    func testAdviceWithoutAVerdictCanBeSaved() {
        var model = KnowledgeComposerModel(category: .nutrition)
        model.form = .foodRule
        model.title = "补铁搭配"
        model.reason = "补铁的同时吃点维生素C，吸收会好一些"

        XCTAssertTrue(model.canSave)
        guard case let .knowledge(data) = model.draft()?.structuredData else {
            return XCTFail("应当是知识条目")
        }
        XCTAssertNil(data.verdict)
    }

    func testAReasonIsStillRequiredEvenWithoutAVerdict() {
        var model = KnowledgeComposerModel(category: .nutrition)
        model.form = .foodRule
        model.title = "螃蟹"

        XCTAssertFalse(model.canSave, "只有标题没有说明，这条对用户没有价值")
    }
}
