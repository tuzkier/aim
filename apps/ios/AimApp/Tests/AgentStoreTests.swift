import XCTest
@testable import AimApp

@MainActor
final class AgentStoreTests: XCTestCase {
    func testCurrentScreenContextIsIncludedInAgentRequest() {
        let store = AgentStore(context: AgentContext(title: "记录", summary: "最近有 2 条身体感受记录。"))

        XCTAssertEqual(
            store.requestMessage(for: "帮我看看最近的情况"),
            "当前页面：记录\n当前页面摘要：最近有 2 条身体感受记录。\n\n用户问题：帮我看看最近的情况"
        )
    }

    func testApprovalIsAFirstClassState() {
        let request = EveInputRequest(
            requestID: "approval-1",
            kind: "tool-approval",
            prompt: "确认调整计划？",
            options: [EveInputOption(id: "approve", label: "确认")],
            toolName: "update_task"
        )
        XCTAssertEqual(AgentSheetState.awaitingApproval(request), .awaitingApproval(request))
        XCTAssertNotEqual(AgentSheetState.awaitingApproval(request), .applied)
    }
}
