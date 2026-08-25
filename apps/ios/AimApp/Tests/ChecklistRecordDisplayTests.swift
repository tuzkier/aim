import XCTest
@testable import AimApp

/// 勾选办事指南里的一条，会存下一条 checklist 记录。这条记录只带 `collection`
/// 和 `item_id`，人能读的标题在内容文件里（`核对杭州生育待遇材料`）。
///
/// 显示时从没把 id 换回标题，于是记录列表和记录详情里直接摆出
/// `maternity-benefits-materials`——一个用户没有任何办法看懂的内部标识。
final class ChecklistRecordDisplayTests: XCTestCase {
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
        XCTAssertFalse(displayed.contains("-"), "slug 形态的字符串不该直接展示")
    }

    /// 老记录没有 title（此功能上线前勾的），也得有句人话。
    func testLegacyRecordsWithoutATitleStillReadSensibly() {
        XCTAssertEqual(record(title: nil, itemID: "anything").displayTitle, "清单条目")
        XCTAssertEqual(record(title: "   ", itemID: "anything").displayTitle, "清单条目")
    }
}
