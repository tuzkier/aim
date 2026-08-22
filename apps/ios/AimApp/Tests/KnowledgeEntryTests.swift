import XCTest
@testable import AimApp

@MainActor
final class KnowledgeEntryTests: XCTestCase {
    private func record(title: String?, data: KnowledgeRecordData) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .knowledge, occurredAt: .now, visibility: .family,
            title: title, content: nil, structuredData: .knowledge(data),
            attachmentRefs: [], createdAt: .now, updatedAt: .now
        )
    }

    private func recipe() -> RecordItem {
        record(title: "菠菜猪肝汤", data: KnowledgeRecordData(
            category: "nutrition", form: .recipe,
            ingredients: ["菠菜 200g", "猪肝 100g"],
            steps: ["猪肝切片焯水", "下菠菜煮 3 分钟", "调味出锅"]))
    }

    /// 摘要要让人不点进去也知道这条讲什么。
    func testARecipeSummarisesItsSizeNotItsText() {
        XCTAssertEqual(KnowledgeEntry(record: recipe())?.subtitle, "2 样食材 · 3 步")
    }

    func testAFoodRuleLeadsWithItsVerdict() {
        let entry = KnowledgeEntry(record: record(title: "咖啡", data: KnowledgeRecordData(
            category: "nutrition", form: .foodRule, verdict: .limit,
            reason: "每日总量有上限，具体请咨询医生")))

        XCTAssertEqual(entry?.subtitle, "可以，但要限量")
    }

    /// 三档而不是能/不能两档——孕期饮食大量情况是「可以但要限量」。
    func testAllThreeVerdictsHaveDistinctWording() {
        let names = [FoodVerdict.safe, .limit, .avoid].map(\.displayName)

        XCTAssertEqual(Set(names).count, 3)
        XCTAssertTrue(names[1].contains("限量"))
    }

    func testAnEntryWithoutATitleIsRejected() {
        XCTAssertNil(KnowledgeEntry(record: record(
            title: nil,
            data: KnowledgeRecordData(category: "nutrition", form: .tip, body: "正文"))))
    }

    func testTheEntryKnowsWhichCategoryCardItBelongsTo() {
        XCTAssertEqual(KnowledgeEntry(record: recipe())?.category, .nutrition)
    }

    /// 后端加了新形态而客户端还没跟上时，不能整条丢掉。
    func testAnUnknownFormStillRendersSomething() {
        let entry = KnowledgeEntry(record: record(title: "未来形态", data: KnowledgeRecordData(
            category: "nutrition", form: .unknown, body: "正文")))

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.subtitle, "正文")
    }
}
