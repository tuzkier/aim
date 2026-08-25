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

    func testAssistantTextRemovesHiddenReasoningBlocks() {
        XCTAssertEqual(
            AgentResponseText.clean("<think>内部推理</think>给你的建议"),
            "给你的建议"
        )
        XCTAssertEqual(
            AgentResponseText.clean("<analysis>工具参数</analysis>最终结果"),
            "最终结果"
        )
    }

    func testToolCallPreludeIsNotPresentedAsAnAssistantAnswer() {
        XCTAssertFalse(AgentResponseText.shouldDisplay(finishReason: "tool-calls"))
        XCTAssertTrue(AgentResponseText.shouldDisplay(finishReason: "stop"))
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

@MainActor
final class AgentSharedSessionTests: XCTestCase {
    /// 快捷入口（记录、事项上的「问问 AIM」）开一段新对话。
    ///
    /// 此前所有入口共享同一段对话，结果是一段里混着十几件不相干的事，
    /// 有了会话列表之后根本没法翻。旧对话不会丢——它已经登记在会话目录里。
    func testFocusStartsAFreshConversationForTheNewContext() {
        let store = AgentStore(context: nil)
        store.messages.append(AgentMessage(text: "早前的问题", isUser: true))

        let newContext = AgentContext(title: "孕期", summary: "孕 6 周")
        store.focus(context: newContext)

        XCTAssertEqual(store.context, newContext)
        XCTAssertTrue(store.messages.isEmpty, "快捷入口应当开新的一段，而不是接着上一段")
        XCTAssertNil(store.sessionID, "新的一段还没有会话 id，发第一句时才建")
    }

    func testRefocusingOverwritesThePreviousContext() {
        let store = AgentStore(context: AgentContext(title: "孕期", summary: "孕 6 周"))
        let recordContext = AgentContext(title: "记录", summary: "恶心，程度 2")

        store.focus(context: recordContext)

        XCTAssertEqual(store.context, recordContext)
    }

    func testAskSetsContextBeforeSending() {
        let store = AgentStore(context: nil)
        let context = AgentContext(title: "记录", summary: "产检：NT")
        let environment = APIEnvironment(
            baseURL: URL(string: "http://localhost")!,
            eveBaseURL: URL(string: "http://localhost")!,
            bearerToken: nil,
            accountID: nil,
            familyID: nil,
            pregnancyID: nil
        )

        store.ask("请帮我理解这条记录", context: context, environment: environment)

        XCTAssertEqual(store.context, context)
        XCTAssertEqual(store.messages.last?.text, "请帮我理解这条记录")
        XCTAssertTrue(store.messages.last?.isUser ?? false)
    }
}
