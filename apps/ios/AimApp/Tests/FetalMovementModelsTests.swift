import XCTest
@testable import AimApp

final class FetalMovementModelsTests: XCTestCase {
    func testRecordTypeRoundTripsItsRawValue() {
        XCTAssertEqual(RecordType(rawValue: "fetal_movement"), .fetalMovement)
        XCTAssertEqual(RecordType.fetalMovement.rawValue, "fetal_movement")
        XCTAssertEqual(RecordType.fetalMovement.displayName, "胎动")
    }

    func testStructuredDataDecodesFromTheAPIShape() throws {
        let json = """
        {"duration_seconds":1920,"count":10,"target":10,"outcome":"reached","taps":[1,2,3,4,5,6,7,8,9,1920]}
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(APIRecordStructuredDataDTO.self, from: json)

        guard case let .fetalMovement(data) = dto.recordData(for: .fetalMovement) else {
            return XCTFail("应当解码为胎动")
        }
        XCTAssertEqual(data.durationSeconds, 1920)
        XCTAssertEqual(data.outcome, .reached)
        XCTAssertEqual(data.taps.count, 10)
    }

    func testUnknownOutcomeFallsBackToUnknownRecordData() throws {
        let json = """
        {"duration_seconds":60,"count":1,"target":10,"outcome":"normal","taps":[5]}
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(APIRecordStructuredDataDTO.self, from: json)
        XCTAssertEqual(dto.recordData(for: .fetalMovement), .unknown)
    }

    func testStructuredDataEncodesTheAPIKeys() throws {
        let data = FetalMovementRecordData(durationSeconds: 7200, count: 6, target: 10, outcome: .under, taps: [1, 2, 3, 4, 5, 6])
        let encoded = try JSONEncoder().encode(APIRecordStructuredDataDTO(recordData: .fetalMovement(data)))
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertEqual(object?["duration_seconds"] as? Int, 7200)
        XCTAssertEqual(object?["outcome"] as? String, "under")
        XCTAssertEqual(object?["target"] as? Int, 10)
        XCTAssertEqual((object?["taps"] as? [Int])?.count, 6)
    }

    func testFormatting() {
        XCTAssertEqual(FetalMovementFormat.duration(40), "不到 1 分钟")
        XCTAssertEqual(FetalMovementFormat.duration(1920), "32 分钟")
        XCTAssertEqual(FetalMovementFormat.duration(1921), "33 分钟")
        XCTAssertEqual(FetalMovementFormat.duration(7200), "2 小时")
        XCTAssertEqual(FetalMovementFormat.duration(4500), "1 小时 15 分钟")
        XCTAssertEqual(
            FetalMovementFormat.summary(.init(durationSeconds: 1920, count: 10, target: 10, outcome: .reached, taps: [])),
            "10 次 · 32 分钟")
        XCTAssertEqual(
            FetalMovementFormat.summary(.init(durationSeconds: 7200, count: 6, target: 10, outcome: .under, taps: [])),
            "2 小时 6 次 · 不足 10 次")
        XCTAssertEqual(
            FetalMovementFormat.summary(.init(durationSeconds: 600, count: 4, target: 10, outcome: .stopped, taps: [])),
            "4 次 · 10 分钟 · 未数完")
    }
}
