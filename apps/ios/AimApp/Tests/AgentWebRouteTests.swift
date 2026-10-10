import XCTest
@testable import AimApp

/// 对话面里点引用胶囊、卡片「查看」后，原生要落到哪个页面。
@MainActor
final class AgentWebRouteTests: XCTestCase {
    func testEncyclopediaRouteKeepsTheEntryID() {
        XCTAssertEqual(AgentWebRoute(body: ["kind": "encyclopedia", "id": "checkup.ogtt"]), .encyclopedia("checkup.ogtt"))
        XCTAssertNil(AgentWebRoute(body: ["kind": "encyclopedia", "id": "不合法"]))
        XCTAssertEqual(AgentWebRoute(body: ["kind": "record", "id": UUID().uuidString]).map { if case .record = $0 { return true } else { return false } }, true)
    }

    /// 编号只认「主题.短名」：缺主题、带路径分隔、大写都不放行——它会被拼进请求路径。
    func testEncyclopediaRouteRejectsMalformedIDs() {
        for bad in ["ogtt", "checkup.", ".ogtt", "checkup/ogtt", "Checkup.ogtt", "checkup.ogtt/../x", "checkup.ogtt\n"] {
            XCTAssertNil(AgentWebRoute(body: ["kind": "encyclopedia", "id": bad]), bad)
        }
        XCTAssertEqual(AgentWebRoute(body: ["kind": "encyclopedia", "id": "body.fetal-movement"]), .encyclopedia("body.fetal-movement"))
    }

    /// 百科条目不预取：详情页自己加载、自己处理下线，所以解析时不能去打接口。
    func testEncyclopediaDestinationResolvesWithoutLoading() async {
        let destinations = AgentDestinations(
            planStore: PlanStore(), recordStore: RecordStore(), libraryStore: LibraryStore(), agentStore: AgentStore()
        )

        let target = await destinations.resolve(.encyclopedia("checkup.ogtt"))

        XCTAssertEqual(target?.id, "encyclopedia-checkup.ogtt")
        XCTAssertFalse(destinations.libraryStore.isLoading)
        XCTAssertNil(destinations.libraryStore.errorMessage)
    }

    /// 只有 404 算「这条资料已下线」；其他失败仍可重试。
    func testOnly404MeansTheEntryIsGone() {
        XCTAssertTrue(APIError.http(status: 404, body: "").isNotFound)
        XCTAssertFalse(APIError.http(status: 500, body: "").isNotFound)
        XCTAssertFalse(APIError.http(status: 401, body: "").isNotFound)
        XCTAssertFalse(APIError.invalidResponse.isNotFound)
        XCTAssertFalse(APIError.notConfigured.isNotFound)
    }
}
