import XCTest
@testable import AimApp

@MainActor
final class LibraryCatalogTests: XCTestCase {
    private func record(
        _ type: RecordType,
        daysAgo: Int,
        data: RecordStructuredData
    ) -> RecordItem {
        let when = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: type, occurredAt: when, visibility: .family,
            title: nil, content: nil, structuredData: data,
            attachmentRefs: [], createdAt: when, updatedAt: when
        )
    }

    private func symptom(_ label: String, daysAgo: Int) -> RecordItem {
        record(.symptom, daysAgo: daysAgo,
               data: .symptom(SymptomRecordData(symptoms: [label], severity: 2, note: nil)))
    }

    private func checkup(daysAgo: Int) -> RecordItem {
        record(.checkup, daysAgo: daysAgo,
               data: .checkup(CheckupRecordData(
                   hospital: "市一医院", examItems: "常规", result: "正常", doctorAdvice: "按时复查")))
    }

    /// 分类目录是数据不是代码：新增一个分类应该是加一条配置。
    func testCatalogDeclaresEveryCategoryOnce() {
        let ids = LibraryCatalog.categories.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count, "分类 id 不能重复")
        XCTAssertTrue(ids.contains(.symptoms))
        XCTAssertTrue(ids.contains(.checkups))
    }

    /// 卡片要显示活数据。没有数据时也得有话说，不能空着一张卡。
    func testSummaryOfAnEmptyCategoryStillReadsAsAnInvitation() {
        let summary = LibraryCategoryID.symptoms.summary(
            from: LibrarySnapshot(records: [], safetyRuleCount: 0)
        )

        XCTAssertFalse(summary.headline.isEmpty)
        XCTAssertTrue(summary.tags.isEmpty)
    }

    func testSymptomSummaryCountsOnlyTheLastSevenDays() {
        let snapshot = LibrarySnapshot(
            records: [
                symptom("腰酸", daysAgo: 1),
                symptom("腰酸", daysAgo: 2),
                symptom("恶心", daysAgo: 3),
                symptom("头晕", daysAgo: 30),
            ],
            safetyRuleCount: 0
        )

        let summary = LibraryCategoryID.symptoms.summary(from: snapshot)

        XCTAssertEqual(summary.headline, "近 7 天 3 条")
    }

    /// 反复出现的症状要带次数——「腰酸 ×2」比「腰酸」更值得被看见。
    func testRepeatedSymptomsAreTaggedWithTheirCount() {
        let snapshot = LibrarySnapshot(
            records: [
                symptom("腰酸", daysAgo: 1),
                symptom("腰酸", daysAgo: 2),
                symptom("恶心", daysAgo: 3),
            ],
            safetyRuleCount: 0
        )

        let summary = LibraryCategoryID.symptoms.summary(from: snapshot)

        XCTAssertEqual(summary.tags.first, "腰酸 ×2")
        XCTAssertTrue(summary.tags.contains("恶心"))
    }

    func testCheckupSummaryCountsAllOfThem() {
        let snapshot = LibrarySnapshot(
            records: [checkup(daysAgo: 3), checkup(daysAgo: 40), checkup(daysAgo: 90)],
            safetyRuleCount: 0
        )

        XCTAssertEqual(LibraryCategoryID.checkups.summary(from: snapshot).headline, "3 次记录")
    }

    func testSafetyRulesSummaryUsesTheLoadedCount() {
        let snapshot = LibrarySnapshot(records: [], safetyRuleCount: 4)

        XCTAssertEqual(LibraryCategoryID.safety.summary(from: snapshot).headline, "4 条")
    }

    /// 分类卡要能带上下文调起 AIM，与时间线头部同一套机制。
    func testEveryCategoryProducesAnAgentContext() {
        let snapshot = LibrarySnapshot(records: [symptom("腰酸", daysAgo: 1)], safetyRuleCount: 2)

        for category in LibraryCatalog.categories {
            let context = category.id.agentContext(from: snapshot)
            XCTAssertFalse(context.title.isEmpty)
            XCTAssertFalse(context.summary.isEmpty, "\(category.id) 的上下文摘要不该为空")
        }
    }

    /// 在产检分类里问 AIM：要带上记录编号，AIM 才能在回答里引用具体那一次。
    func testCheckupContextCarriesTheLatestRecordID() {
        let latest = checkup(daysAgo: 1)
        let snapshot = LibrarySnapshot(records: [checkup(daysAgo: 20), latest], safetyRuleCount: 0)

        let agent = LibraryCategoryID.checkups.agentContext(from: snapshot).summary
        let ask = LibraryCategoryID.checkups.askContext(from: snapshot).summary

        XCTAssertTrue(agent.contains("记录编号："), agent)
        XCTAssertTrue(agent.contains(latest.id.uuidString), agent)
        XCTAssertTrue(agent.contains("常规"), "编号后要附上日期与标题，AIM 才知道是哪一次")
        XCTAssertTrue(ask.contains(latest.id.uuidString), ask)
    }

    func testSymptomContextCarriesTheLatestRecordIDAndIgnoresOtherTypes() {
        let latest = symptom("腰酸", daysAgo: 0)
        let other = checkup(daysAgo: 0)
        let snapshot = LibrarySnapshot(records: [symptom("恶心", daysAgo: 3), latest, other], safetyRuleCount: 0)

        let summary = LibraryCategoryID.symptoms.agentContext(from: snapshot).summary

        XCTAssertTrue(summary.contains(latest.id.uuidString), summary)
        XCTAssertFalse(summary.contains(other.id.uuidString), "身体感受分类不带产检记录的编号")
    }

    /// 只带最近 5 条，按时间倒序——上下文不能随记录数无限变长。
    func testRecordIDsAreLimitedToTheLatestFiveNewestFirst() {
        let records = (1...7).map { checkup(daysAgo: $0) }
        let snapshot = LibrarySnapshot(records: records.shuffled(), safetyRuleCount: 0)

        let summary = LibraryCategoryID.checkups.agentContext(from: snapshot).summary
        let line = summary.components(separatedBy: "\n").first { $0.hasPrefix("记录编号：") } ?? ""

        for kept in records.prefix(5) { XCTAssertTrue(line.contains(kept.id.uuidString)) }
        for dropped in records.suffix(2) { XCTAssertFalse(summary.contains(dropped.id.uuidString)) }
        let positions = records.prefix(5).compactMap { line.range(of: $0.id.uuidString)?.lowerBound }
        XCTAssertEqual(positions, positions.sorted(), "最近的在前")
    }

    /// 没有记录时不加空的编号行；其他分类不带编号。
    func testNoRecordIDLineWithoutRecordsOrOutsideCheckupsAndSymptoms() {
        let empty = LibrarySnapshot(records: [], safetyRuleCount: 0)
        XCTAssertFalse(LibraryCategoryID.checkups.agentContext(from: empty).summary.contains("记录编号"))

        let snapshot = LibrarySnapshot(records: [checkup(daysAgo: 1)], safetyRuleCount: 0)
        XCTAssertFalse(LibraryCategoryID.questions.agentContext(from: snapshot).summary.contains("记录编号"))
    }
}

@MainActor
final class LibraryStep2CatalogTests: XCTestCase {
    private func question(_ text: String, answered: Bool, daysAgo: Int = 0) -> RecordItem {
        let when = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .question, occurredAt: when, visibility: .family,
            title: nil, content: text,
            structuredData: .question(QuestionRecordData(answered: answered, answer: nil)),
            attachmentRefs: [], createdAt: when, updatedAt: when
        )
    }

    private func checked(_ collection: String, _ itemID: String, done: Bool) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .checklist, occurredAt: .now, visibility: .family,
            title: nil, content: nil,
            structuredData: .checklist(
                ChecklistRecordData(collection: collection, itemID: itemID, done: done)),
            attachmentRefs: [], createdAt: .now, updatedAt: .now
        )
    }

    /// 卡片要回答「还有几个没问」，而不是「一共攒了几个」——
    /// 已经问过的不该继续占用注意力。
    func testQuestionSummaryCountsOnlyTheUnanswered() {
        let snapshot = LibrarySnapshot(
            records: [
                question("能继续游泳吗", answered: false, daysAgo: 1),
                question("能喝咖啡吗", answered: false, daysAgo: 2),
                question("要补钙吗", answered: true, daysAgo: 3),
            ],
            safetyRuleCount: 0
        )

        let summary = LibraryCategoryID.questions.summary(from: snapshot)

        XCTAssertEqual(summary.headline, "攒了 2 个问题")
    }

    func testQuestionSummaryShowsTheMostRecentUnansweredOne() {
        let snapshot = LibrarySnapshot(
            records: [
                question("旧问题", answered: false, daysAgo: 9),
                question("新问题", answered: false, daysAgo: 1),
            ],
            safetyRuleCount: 0
        )

        XCTAssertEqual(LibraryCategoryID.questions.summary(from: snapshot).detail, "新问题")
    }

    func testQuestionSummaryWhenEverythingIsAnswered() {
        let snapshot = LibrarySnapshot(
            records: [question("问过了", answered: true)], safetyRuleCount: 0
        )

        XCTAssertEqual(LibraryCategoryID.questions.summary(from: snapshot).headline, "都问过了")
    }

    /// 清单进度来自「内容库的条目总数」与「已勾选的记录数」的交叉。
    func testPreparationSummaryShowsProgressAgainstTheContentLibrary() {
        let snapshot = LibrarySnapshot(
            records: [
                checked("preparation", "documents", done: true),
                checked("preparation", "baby-care", done: true),
                checked("preparation", "feeding", done: false),
                checked("paperwork", "other", done: true),
            ],
            safetyRuleCount: 0,
            collectionSizes: ["preparation": 7]
        )

        XCTAssertEqual(LibraryCategoryID.preparation.summary(from: snapshot).headline, "待产包 2/7")
    }

    func testPaperworkSummaryUsesItsOwnCollection() {
        let snapshot = LibrarySnapshot(
            records: [checked("hangzhou", "maternity-benefits-materials", done: true)],
            safetyRuleCount: 0,
            collectionSizes: ["hangzhou": 1]
        )

        XCTAssertEqual(LibraryCategoryID.paperwork.summary(from: snapshot).headline, "1/1 已办妥")
    }

    /// 内容还没加载出来时不能显示 "0/0" —— 那看起来像没有内容。
    func testChecklistSummaryBeforeContentLoads() {
        let snapshot = LibrarySnapshot(records: [], safetyRuleCount: 0)

        XCTAssertEqual(
            LibraryCategoryID.preparation.summary(from: snapshot).headline, "待产包与婴儿用品")
    }

    /// 「吃什么」：百科饮食主题有条目时用它的数量；生产不加载草稿时回退到 nutrition 集合。
    func testNutritionSummaryPrefersEncyclopediaAndFallsBackToNutritionCollection() {
        let fallback = LibrarySnapshot(collectionSizes: ["nutrition": 7])
        let both = LibrarySnapshot(collectionSizes: ["nutrition": 7], encyclopediaCounts: ["diet": 12])
        let neither = LibrarySnapshot()

        XCTAssertEqual(LibraryCategoryID.nutrition.summary(from: fallback).headline, "7 条饮食提示")
        XCTAssertEqual(LibraryCategoryID.nutrition.summary(from: both).headline, "12 条饮食提示")
        XCTAssertEqual(LibraryCategoryID.nutrition.summary(from: neither).headline, "食谱与禁忌，即将上线")
    }
}
