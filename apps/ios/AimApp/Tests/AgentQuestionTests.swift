import XCTest
@testable import AimApp

/// Agent 反问和「写操作待批准」此前共用一条路：两者都被渲染成
/// 「确认计划变更」浮层，只有确认/取消两个按钮。模型问「你最看重什么」，
/// 用户点「确认执行」，发回去的字面答案是 "approve"——问题根本没法回答。
///
/// 下面两段 JSON 是从生产环境 `/eve/v1/session/{id}/stream` 上原样抓下来的，
/// 不是照着猜的形状写的。第一版判据（「没有 toolName 就是提问」）正是因为
/// 想当然而错了：提问同样带 action。
enum EveInputRequestFixture {
    /// 真实提问：`kind=question`、`action.toolName=ask_question`、没有 options。
    static let question = """
    {"requestId":"call_00_onC8lw","kind":"question","display":"text","allowFreeform":true,
     "prompt":"请问你想记录哪道菜谱？",
     "action":{"callId":"call_00_onC8lw","kind":"tool-call","toolName":"ask_question",
               "input":{"allowFreeform":true,"prompt":"请问你想记录哪道菜谱？"}}}
    """

    /// 真实写操作批准：`kind=tool-approval`、`allowFreeform=false`、options 是 approve/cancel。
    static let approval = """
    {"requestId":"call_01_zz","kind":"tool-approval","allowFreeform":false,
     "prompt":"要记下这条菜谱吗？",
     "options":[{"id":"approve","label":"Approve"},{"id":"cancel","label":"Cancel"}],
     "action":{"callId":"call_01_zz","kind":"tool-call","toolName":"create_knowledge",
               "input":{"title":"菠菜猪肝汤","category":"nutrition","form":"recipe"}}}
    """

    static func decode(_ json: String) -> EveInputRequest {
        try! JSONDecoder().decode(EveInputRequest.self, from: Data(json.utf8))
    }
}

final class AgentQuestionTests: XCTestCase {
    func testRealQuestionPayloadIsRecognised() {
        let question = AgentQuestion(request: EveInputRequestFixture.decode(EveInputRequestFixture.question))
        XCTAssertEqual(question?.prompt, "请问你想记录哪道菜谱？")
        XCTAssertTrue(question?.allowsFreeform ?? false, "线上的提问允许自由作答")
        XCTAssertEqual(question?.options, [], "Eve 这类提问一个选项都不发")
    }

    func testRealApprovalPayloadIsNotAQuestion() {
        XCTAssertNil(AgentQuestion(request: EveInputRequestFixture.decode(EveInputRequestFixture.approval)))
    }

    /// 提问也带 action——这正是第一版判据错的地方，钉住它。
    func testQuestionsAlsoCarryAnActionSoToolNamePresenceIsNotTheTest() {
        let request = EveInputRequestFixture.decode(EveInputRequestFixture.question)
        XCTAssertEqual(request.toolName, "ask_question")
        XCTAssertNotNil(AgentQuestion(request: request))
    }

    /// 写操作漏发 kind 时解码会兜底成 "question"。这种情况必须仍然走确认，
    /// 否则模型可以靠省略一个字段绕过权限边界。
    func testWriteToolWithoutAKindStillRequiresApproval() {
        let request = EveInputRequestFixture.decode("""
        {"requestId":"x","prompt":"要记下这条菜谱吗？",
         "action":{"callId":"x","kind":"tool-call","toolName":"create_knowledge","input":{}}}
        """)
        XCTAssertEqual(request.kind, "question", "解码确实兜底成了 question")
        XCTAssertNil(AgentQuestion(request: request), "但它带的是写工具，不能当提问放行")
    }

    func testRequestWithoutAPromptIsNotAQuestion() {
        let request = EveInputRequestFixture.decode("""
        {"requestId":"x","kind":"question","prompt":"   ","allowFreeform":true}
        """)
        XCTAssertNil(AgentQuestion(request: request))
    }

    /// options 此前被解码进来后一路丢弃，UI 里一次都没渲染过。
    func testOptionsSurviveIntoTheQuestion() {
        let request = EveInputRequestFixture.decode("""
        {"requestId":"x","kind":"question","prompt":"你最看重什么？","allowFreeform":false,
         "options":[{"id":"iron","label":"补铁"},{"id":"calcium","label":"补钙"}]}
        """)
        XCTAssertEqual(
            AgentQuestion(request: request)?.options,
            [EveInputOption(id: "iron", label: "补铁"), EveInputOption(id: "calcium", label: "补钙")]
        )
    }
}

@MainActor
final class AgentQuestionRoutingTests: XCTestCase {
    private func inputRequestedEvent(_ requestJSON: String) -> EveEvent {
        EveEvent(
            type: .inputRequested,
            rawType: "input.requested",
            eventID: "evt-1",
            streamIndex: 1,
            data: Data("{\"requests\":[\(requestJSON)]}".utf8)
        )
    }

    func testQuestionLandsInTheConversationInsteadOfTheApprovalSheet() {
        let store = AgentStore(context: nil)
        store.consume(inputRequestedEvent(EveInputRequestFixture.question))

        guard case .awaitingAnswer = store.state else {
            return XCTFail("反问应进入等待回答态，而不是等待批准")
        }
        XCTAssertEqual(store.messages.last?.text, "请问你想记录哪道菜谱？")
        XCTAssertFalse(store.messages.last?.isUser ?? true, "问句是 Agent 说的")
    }

    /// 写操作仍然要走浮层确认——那是权限边界，不能因为这次改动被削弱。
    func testToolApprovalStillGoesToTheApprovalSheet() {
        let store = AgentStore(context: nil)
        store.consume(inputRequestedEvent(EveInputRequestFixture.approval))

        guard case .awaitingApproval = store.state else {
            return XCTFail("写操作必须仍然走确认浮层")
        }
        XCTAssertTrue(store.messages.isEmpty, "待批准的写操作不该混进对话流")
    }

    func testAnsweringWithAnOptionRecordsWhatTheUserChose() {
        let store = AgentStore(context: nil)
        store.sessionID = "s-1"
        store.consume(inputRequestedEvent("""
        {"requestId":"q-1","kind":"question","prompt":"你最看重什么？","allowFreeform":false,
         "options":[{"id":"iron","label":"补铁"}]}
        """))

        store.answer(optionID: "iron", label: "补铁", environment: .test)

        XCTAssertEqual(store.messages.last?.text, "补铁")
        XCTAssertTrue(store.messages.last?.isUser ?? false, "选项是用户的回答")
    }

    /// 输入框打的字要回到这次提问上，而不是另起一轮对话——
    /// 否则模型收不到答案，会一直卡在等待里。
    func testTypedTextAnswersThePendingQuestion() {
        let store = AgentStore(context: nil)
        store.sessionID = "s-1"
        store.consume(inputRequestedEvent(EveInputRequestFixture.question))

        store.draft = "菠菜猪肝汤，补铁的"
        store.send(environment: .test)

        XCTAssertEqual(store.messages.last?.text, "菠菜猪肝汤，补铁的")
        XCTAssertNil(store.pendingQuestion, "答完之后不该还停在等待回答态")
    }
}

extension APIEnvironment {
    static var test: APIEnvironment {
        APIEnvironment(
            baseURL: URL(string: "http://localhost")!,
            eveBaseURL: URL(string: "http://localhost")!,
            bearerToken: nil,
            accountID: nil,
            familyID: nil,
            pregnancyID: nil
        )
    }
}
