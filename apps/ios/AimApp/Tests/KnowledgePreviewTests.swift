import XCTest
@testable import AimApp

@MainActor
final class KnowledgePreviewTests: XCTestCase {
    private func request(input: [String: Any]) -> EveInputRequest {
        let payload: [String: Any] = [
            "requestId": "aitxt-1",
            "kind": "tool-approval",
            "prompt": "Approve tool call: create_knowledge",
            "options": [["id": "approve", "label": "Approve"],
                        ["id": "cancel", "label": "Cancel"]],
            "action": ["callId": "c1", "kind": "tool-call",
                       "toolName": "create_knowledge", "input": input],
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return try! JSONDecoder().decode(EveInputRequest.self, from: data)
    }

    /// 审批请求里带着工具入参，预览卡要靠它渲染出「这条菜谱长什么样」，
    /// 而不是只显示 Eve 默认的英文 "Approve tool call: create_knowledge"。
    func testARecipeApprovalCarriesItsContent() {
        let preview = KnowledgePreview(request: request(input: [
            "title": "菠菜猪肝汤", "category": "nutrition", "form": "recipe",
            "ingredients": ["菠菜 200g", "猪肝 100g"],
            "steps": ["猪肝焯水", "下菠菜煮 3 分钟"],
        ]))

        XCTAssertEqual(preview?.title, "菠菜猪肝汤")
        XCTAssertEqual(preview?.data.ingredients?.count, 2)
        XCTAssertEqual(preview?.data.form, .recipe)
    }

    func testAFoodRuleApprovalCarriesItsVerdict() {
        let preview = KnowledgePreview(request: request(input: [
            "title": "咖啡", "category": "nutrition", "form": "food_rule",
            "verdict": "limit", "reason": "每日总量有上限",
        ]))

        XCTAssertEqual(preview?.data.verdict, .limit)
    }

    /// 其他工具的审批请求不该被当成知识条目。
    func testOtherToolsDoNotProduceAKnowledgePreview() {
        let payload: [String: Any] = [
            "requestId": "r", "kind": "tool-approval", "options": [],
            "action": ["toolName": "update_task", "kind": "tool-call", "input": ["taskId": "x"]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let other = try! JSONDecoder().decode(EveInputRequest.self, from: data)

        XCTAssertNil(KnowledgePreview(request: other))
    }

    func testAnApprovalWithoutContentIsNotPreviewable() {
        XCTAssertNil(KnowledgePreview(request: request(input: ["category": "nutrition"])))
    }
}
