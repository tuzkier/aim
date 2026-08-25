import XCTest
@testable import AimApp

@MainActor
final class NutritionSectionTests: XCTestCase {
    private func entry(_ title: String, form: KnowledgeForm,
                       purposes: [String]? = nil, verdict: FoodVerdict? = nil) -> KnowledgeEntry {
        let record = RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .knowledge, occurredAt: .now, visibility: .family,
            title: title, content: nil,
            structuredData: .knowledge(KnowledgeRecordData(
                category: "nutrition", form: form,
                ingredients: form == .recipe ? ["食材"] : nil,
                steps: form == .recipe ? ["步骤"] : nil,
                verdict: verdict, reason: form == .foodRule ? "原因" : nil,
                purposes: purposes)),
            attachmentRefs: [], createdAt: .now, updatedAt: .now)
        return KnowledgeEntry(record: record)!
    }

    /// 菜谱和饮食提示是两个场景：找菜做饭 vs 查能不能吃。
    /// 混在一个列表里两个都不好用。
    func testRecipesAndAdviceAreSeparated() {
        let entries = [
            entry("菠菜猪肝汤", form: .recipe, purposes: ["补铁"]),
            entry("咖啡", form: .foodRule, verdict: .limit),
            entry("补铁搭配", form: .foodRule),
        ]

        XCTAssertEqual(NutritionSection.recipes.entries(from: entries).map(\.title),
                       ["菠菜猪肝汤"])
        XCTAssertEqual(Set(NutritionSection.advice.entries(from: entries).map(\.title)),
                       Set(["咖啡", "补铁搭配"]))
    }

    /// 用途标签是找菜谱的入口——攒到二三十条时，标题没法找。
    /// 按频次排：攒得最多的用途放最前，那是当前最关心的。
    func testPurposeFiltersAreOrderedByHowOftenTheyAreUsed() {
        let entries = [
            entry("菠菜猪肝汤", form: .recipe, purposes: ["补铁"]),
            entry("红枣粥", form: .recipe, purposes: ["补铁", "补气"]),
            entry("姜茶", form: .recipe, purposes: ["缓解孕吐"]),
        ]

        let purposes = NutritionSection.purposes(in: entries)

        XCTAssertEqual(purposes.first, "补铁", "用得最多的排最前")
        XCTAssertEqual(Set(purposes), Set(["补铁", "补气", "缓解孕吐"]))
    }

    func testFilteringByPurposeKeepsOnlyMatchingRecipes() {
        let entries = [
            entry("菠菜猪肝汤", form: .recipe, purposes: ["补铁"]),
            entry("姜茶", form: .recipe, purposes: ["缓解孕吐"]),
        ]

        let filtered = NutritionSection.recipes.entries(from: entries, purpose: "补铁")

        XCTAssertEqual(filtered.map(\.title), ["菠菜猪肝汤"])
    }

    /// 没有用途的菜谱不能因为筛选就永远消失——但不选筛选时要能看到。
    func testRecipesWithoutPurposesStillShowWhenUnfiltered() {
        let entries = [entry("白粥", form: .recipe)]

        XCTAssertEqual(NutritionSection.recipes.entries(from: entries).count, 1)
        XCTAssertTrue(NutritionSection.recipes.entries(from: entries, purpose: "补铁").isEmpty)
    }

    /// 结论可选，所以摘要不能假设一定有。
    func testAdviceWithoutAVerdictStillReadsWell() {
        let advice = entry("补铁搭配", form: .foodRule)

        XCTAssertFalse(advice.subtitle.isEmpty)
        XCTAssertNotEqual(advice.subtitle, "待确认", "没有结论时不该显示「待确认」")
    }
}
