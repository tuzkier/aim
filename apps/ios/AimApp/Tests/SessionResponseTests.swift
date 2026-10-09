import XCTest
@testable import AimApp

final class SessionResponseTests: XCTestCase {
    private let base = """
    {
      "account_id": "11111111-1111-1111-1111-111111111111",
      "phone": "13800000001",
      "family_id": "22222222-2222-2222-2222-222222222222",
      "pregnancy_id": null,
      "role": "mother",
      "token": "aim.v1.demo"
    """

    func testDeletionCancelledDefaultsToFalseWhenMissing() throws {
        let data = (base + "}").data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder.aim.decode(SessionResponse.self, from: data).deletionCancelled)
    }

    func testDeletionCancelledIsDecoded() throws {
        let data = (base + ", \"deletion_cancelled\": true}").data(using: .utf8)!
        XCTAssertTrue(try JSONDecoder.aim.decode(SessionResponse.self, from: data).deletionCancelled)
    }
}
