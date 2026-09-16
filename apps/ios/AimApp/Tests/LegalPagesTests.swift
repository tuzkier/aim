import XCTest
@testable import AimApp

final class LegalPagesTests: XCTestCase {
    func testLegalURLsLiveUnderTheGatewayLegalPath() {
        let gateway = URL(string: "http://127.0.0.1:8080")!
        XCTAssertEqual(AgentWebScheme.legalURL(.privacy, gateway: gateway).absoluteString,
                       "http://127.0.0.1:8080/legal/privacy.html")
        XCTAssertEqual(AgentWebScheme.legalURL(.terms, gateway: gateway).absoluteString,
                       "http://127.0.0.1:8080/legal/terms.html")
    }

    func testLegalURLIgnoresTrailingSlashOnGateway() {
        let gateway = URL(string: "http://121.40.205.28/")!
        XCTAssertEqual(AgentWebScheme.legalURL(.terms, gateway: gateway).absoluteString,
                       "http://121.40.205.28/legal/terms.html")
    }
}
