import XCTest
@testable import AimApp

/// 线上撞到的：让 AIM 把几道菜收进菜谱，确认卡弹出、点了「收录」、卡片消失，
/// 然后一道也没入库，那段对话回头看还少了一截。
///
/// 模型在同一轮里发起多个 `create_knowledge`，Eve 把这一轮的审批打成**一个批次**
/// 下发——`input.requested` 的 `requests` 是数组。Store 此前取 `.first` 丢弃其余，
/// 而 Eve 整批凑齐才结算（`buildResolvedInputBatch` 在批次不完整时返回 undefined），
/// 于是整轮一直 parked：它「withheld model output」不发（对话少一截），批内工具
/// 一个都不执行（菜一道也没存）。
///
/// Eve 的协议注释把这条写在明处：consumers must correlate action lifecycles by
/// call ID rather than assume one event contains every call from an assistant step。
@MainActor
final class AgentApprovalBatchTests: XCTestCase {
    /// 一个事件里的三条审批都必须留住。只认第一条，另外两条就再也没有入口，
    /// 整轮永远不结算。
    func testEveryRequestInAnApprovalBatchIsKept() {
        let store = AgentStore()
        store.consume(Self.approvalBatchEvent())

        XCTAssertEqual(
            store.pendingApprovals.map(\.requestID),
            ["approval-1", "approval-2", "approval-3"]
        )
    }

    /// 逐条回答的过程中不能提前把响应发回 Eve——批次不完整，发过去也不结算，
    /// 反而把「还差几条」这个状态弄丢。
    func testBatchIsNotResolvedUntilEveryRequestIsAnswered() {
        let store = AgentStore()
        store.consume(Self.approvalBatchEvent())

        store.recordApproval(requestID: "approval-1", approved: true)
        XCTAssertFalse(store.isApprovalBatchComplete, "还差两条")

        store.recordApproval(requestID: "approval-2", approved: false)
        XCTAssertFalse(store.isApprovalBatchComplete, "还差一条")

        store.recordApproval(requestID: "approval-3", approved: true)
        XCTAssertTrue(store.isApprovalBatchComplete, "三条都有回音了，这时才能发回 Eve")
    }

    /// 否决其中一条不代表放弃整批：剩下的仍要答完，否则批次不结算，
    /// 已经同意的那几条也一起卡住。
    func testDenyingOneRequestStillLeavesTheRestPending() {
        let store = AgentStore()
        store.consume(Self.approvalBatchEvent())

        store.recordApproval(requestID: "approval-2", approved: false)

        XCTAssertEqual(
            store.unansweredApprovals.map(\.requestID),
            ["approval-1", "approval-3"]
        )
    }

    // MARK: - 载荷

    /// 三道菜的真实形状：一个 input.requested，requests 里三条 tool-approval。
    private static func approvalBatchEvent() -> EveEvent {
        let dishes = [
            ("approval-1", "菠菜猪肝汤"),
            ("approval-2", "红枣枸杞蒸蛋"),
            ("approval-3", "牛肉时蔬粥"),
        ]
        let requests = dishes.map { id, title in
            """
            {
              "requestId": "\(id)",
              "kind": "tool-approval",
              "allowFreeform": false,
              "options": [{"id": "approve", "label": "收录"}],
              "action": {
                "toolName": "create_knowledge",
                "input": {"title": "\(title)", "category": "nutrition", "form": "recipe"}
              }
            }
            """
        }
        let json = "{\"requests\":[\(requests.joined(separator: ","))]}"
        return EveEvent(
            type: .inputRequested,
            rawType: "input.requested",
            eventID: "evt-1",
            streamIndex: 7,
            data: Data(json.utf8)
        )
    }
}
