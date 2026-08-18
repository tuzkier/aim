import XCTest
@testable import AimApp

final class AgentChangePreviewTests: XCTestCase {
    func testRendersBeforeAndAfterWithArrow() {
        let row = AgentChangeRow(symbol: "calendar", field: "检查日期", before: "今天", after: "8月19日")
        XCTAssertEqual(row.valueText, "今天 → 8月19日")
    }

    func testRendersOnlyAfterWhenBeforeIsMissing() {
        let row = AgentChangeRow(symbol: "person", field: "家庭分工", before: nil, after: "由爸爸负责")
        XCTAssertEqual(row.valueText, "由爸爸负责")
    }

    func testFallsBackToPromptWhenRequestHasNoStructuredChanges() {
        let request = EveInputRequest(requestID: "r1", kind: "approval", prompt: "要执行这项计划变更吗？",
                                      options: [], toolName: nil, changes: nil, qualifier: nil)
        let preview = AgentChangePreview.from(request)
        XCTAssertEqual(preview.understanding, "要执行这项计划变更吗？")
        XCTAssertTrue(preview.changes.isEmpty)
    }

    func testApplyButtonTitleCountsChanges() {
        let preview = AgentChangePreview(
            understanding: "医生把系统超声检查改到下周三",
            qualifier: "这是日程变化，不涉及新的医疗判断。",
            changes: [
                AgentChangeRow(symbol: "calendar", field: "检查日期", before: "今天", after: "8月19日"),
                AgentChangeRow(symbol: "arrow.clockwise", field: "材料准备", before: "8月20日", after: "8月18日")
            ]
        )
        XCTAssertEqual(preview.applyTitle, "应用 2 项变更")
    }

    func testApplyButtonTitleWithoutStructuredChanges() {
        let preview = AgentChangePreview(understanding: "问题", qualifier: nil, changes: [])
        XCTAssertEqual(preview.applyTitle, "确认执行")
    }
}
