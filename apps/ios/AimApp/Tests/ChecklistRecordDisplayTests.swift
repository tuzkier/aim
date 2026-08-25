import XCTest
@testable import AimApp

/// 勾选办事指南里的一条，会存下一条 checklist 记录。这条记录只带 `collection`
/// 和 `item_id`，人能读的标题在内容文件里（`核对杭州生育待遇材料`）。
///
/// 显示时从没把 id 换回标题，于是记录列表和记录详情里直接摆出
/// `maternity-benefits-materials`——一个用户没有任何办法看懂的内部标识。
@MainActor
final class ChecklistRecordDisplayTests: XCTestCase {
    override func tearDown() {
        ContentTitleIndex.reset()
        super.tearDown()
    }

    private func record(title: String?, itemID: String) -> RecordItem {
        RecordItem(
            id: UUID(),
            pregnancyID: UUID(),
            familyID: UUID(),
            authorAccountID: UUID(),
            type: .checklist,
            occurredAt: .now,
            visibility: .family,
            title: title,
            content: nil,
            structuredData: .checklist(
                ChecklistRecordData(collection: "hangzhou", itemID: itemID, done: true)
            ),
            attachmentRefs: [],
            createdAt: .now,
            updatedAt: .now
        )
    }

    func testTheTitleIsUsedWhenTheRecordCarriesOne() {
        XCTAssertEqual(
            record(title: "核对杭州生育待遇材料", itemID: "maternity-benefits-materials").displayTitle,
            "核对杭州生育待遇材料"
        )
    }

    /// 这条是核心：内部 id 永远不该出现在界面上。
    func testTheInternalIdIsNeverShown() {
        let displayed = record(title: nil, itemID: "maternity-benefits-materials").displayTitle
        XCTAssertFalse(
            displayed.contains("maternity-benefits-materials"),
            "内部 id 漏到了界面上：\(displayed)"
        )
    }

    /// 没有 title 的老记录（这个功能上线前勾的）也要显示真标题——
    /// 换成一句「清单条目」，信息量比原来那个 slug 还少。
    func testALegacyRecordResolvesItsTitleFromTheContentIndex() {
        ContentTitleIndex.register([
            "hangzhou": ContentCollection(
                id: "hangzhou-pregnancy-benefits",
                source: "杭州市人力资源和社会保障局公开信息",
                sourceURL: "https://hrss.hangzhou.gov.cn/",
                items: [
                    ContentItem(
                        id: "maternity-benefits-materials",
                        title: "核对杭州生育待遇材料",
                        summary: "仅提供核对入口。",
                        verificationURL: nil,
                        group: nil
                    )
                ]
            )
        ])

        XCTAssertEqual(
            record(title: nil, itemID: "maternity-benefits-materials").displayTitle,
            "核对杭州生育待遇材料"
        )
    }

    /// 索引里也查不到时才用兜底文案——但仍然不能是 id。
    func testAnUnknownItemFallsBackToAReadableLabel() {
        XCTAssertEqual(record(title: nil, itemID: "never-seen").displayTitle, "清单条目")
    }
}
