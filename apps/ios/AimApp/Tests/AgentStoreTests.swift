import WebKit
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

    func testQuickEntryPayloadCarriesPageContextAndScope() throws {
        let family = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let pregnancy = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let environment = APIEnvironment(
            baseURL: URL(string: "http://127.0.0.1:8100")!,
            eveBaseURL: URL(string: "http://127.0.0.1:2210")!,
            bearerToken: "aim.v1.\"quoted\"",
            accountID: nil,
            familyID: family,
            pregnancyID: pregnancy
        )
        let payload = AgentWebView.contextPayload(
            environment: environment,
            colorScheme: .dark,
            entry: .new(pageContext: AgentContext(title: "番茄炒蛋", summary: "菜谱"), autoSend: nil)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["token"] as? String, "aim.v1.\"quoted\"")
        XCTAssertEqual(object["theme"] as? String, "dark")
        XCTAssertEqual(object["familyId"] as? String, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(object["pregnancyId"] as? String, "33333333-3333-3333-3333-333333333333")
        let entry = try XCTUnwrap(object["entry"] as? [String: Any])
        XCTAssertEqual(entry["mode"] as? String, "new")
        XCTAssertEqual((entry["pageContext"] as? [String: String])?["title"], "番茄炒蛋")
        XCTAssertNil(entry["autoSend"])
    }

    func testTabEntryResumes() throws {
        let environment = APIEnvironment(
            baseURL: URL(string: "http://127.0.0.1:8100")!,
            eveBaseURL: URL(string: "http://127.0.0.1:2210")!,
            bearerToken: nil,
            accountID: nil,
            familyID: nil,
            pregnancyID: nil
        )
        let payload = AgentWebView.contextPayload(environment: environment, colorScheme: .light, entry: .resume)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )
        XCTAssertEqual((object["entry"] as? [String: String])?["mode"], "resume")
        XCTAssertNil(object["familyId"])
    }

    func testAnalysisPreparesAnAutoSendInsteadOfCallingEve() {
        let store = AgentStore()
        store.prepareAnalysis("请帮我理解这条记录", context: AgentContext(title: "记录", summary: "症状：头晕"))
        XCTAssertEqual(store.pendingAutoSend, "请帮我理解这条记录")
        XCTAssertEqual(store.context?.title, "记录")
        XCTAssertTrue(store.messages.isEmpty)
    }

    func testRefreshRequestsDuringARunCollapseIntoOneMorePass() async {
        var batches: [Set<String>] = []
        var release: CheckedContinuation<Void, Never>?
        let coalescer = AgentRefreshCoalescer { kinds in
            batches.append(kinds)
            if batches.count == 1 {
                await withCheckedContinuation { release = $0 }
            }
        }

        let first = Task { await coalescer.request(["task"]) }
        // 等第一轮真正挂起在 perform 里。
        while release == nil { await Task.yield() }
        // 第一轮还没结束时又来了 3 个通知：不该各跑一轮。
        await coalescer.request(["task"])
        await coalescer.request(["record"])
        await coalescer.request(["task", "knowledge"])
        release?.resume()
        await first.value

        XCTAssertEqual(batches, [["task"], ["task", "record", "knowledge"]])
    }

    /// iOS 在后台回收网页进程后，WebView 会一直白着——必须自己重新加载。
    func testWebViewReloadsWhenItsContentProcessIsKilled() {
        let coordinator = AgentWebView.Coordinator(onNavigate: { _ in }, onTurnFinished: { _ in })
        let webView = ReloadSpyWebView()

        coordinator.webViewWebContentProcessDidTerminate(webView)

        XCTAssertTrue(webView.reloaded)
    }
}

private final class ReloadSpyWebView: WKWebView {
    var reloaded = false
    override func reload() -> WKNavigation? {
        reloaded = true
        return nil
    }
}
