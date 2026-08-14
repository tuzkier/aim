import XCTest

final class AgentStoreTests: XCTestCase {
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
