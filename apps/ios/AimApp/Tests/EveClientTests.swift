import Foundation
import XCTest
@testable import AimApp

final class EveClientTests: XCTestCase {
    func testDecoderHandlesSplitLinesAndDeduplicatesEvents() throws {
        let first = Data("{\"type\":\"session.started\",\"data\":{},\"meta\":{\"id\":\"evt-1\"}}\n".utf8)
        let second = Data("{\"type\":\"session.waiting\",\"data\":{\"wait\":\"next-user-message\"},\"meta\":{\"id\":\"evt-2\"}}\n".utf8)
        var decoder = EveNDJSONDecoder()
        XCTAssertEqual(try decoder.append(first.prefix(18)).count, 0)
        XCTAssertEqual(try decoder.append(first.dropFirst(18)).count, 1)
        XCTAssertEqual(try decoder.append(second).count, 1)
        XCTAssertEqual(try decoder.append(first).count, 0)
    }

    func testUnknownEventRemainsVisibleToClient() throws {
        var decoder = EveNDJSONDecoder()
        let events = try decoder.append(Data("{\"type\":\"future.event\",\"data\":{},\"meta\":{\"id\":\"evt-3\"}}\n".utf8))
        XCTAssertEqual(events.first?.type, .unknown("future.event"))
        XCTAssertEqual(events.first?.streamIndex, 1)
    }
}
