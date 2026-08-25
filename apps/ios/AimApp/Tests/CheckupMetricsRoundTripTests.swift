import XCTest
@testable import AimApp

@MainActor
final class CheckupMetricsRoundTripTests: XCTestCase {
    /// 服务器返回的 metrics 必须能被解出来，否则趋势条和「本周关注」
    /// 的血压规则永远没有数据——界面看起来正常，功能是死的。
    func testMetricsSurviveDecodingFromTheServer() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "pregnancy_id": "22222222-2222-2222-2222-222222222222",
          "family_id": "33333333-3333-3333-3333-333333333333",
          "author_account_id": "44444444-4444-4444-4444-444444444444",
          "type": "checkup",
          "occurred_at": "2026-08-14T09:00:00Z",
          "visibility": "family",
          "title": null,
          "content": null,
          "structured_data": {
            "hospital": "市一医院", "exam_items": "常规产检",
            "result": "正常", "doctor_advice": "按时复查",
            "metrics": {"weight_kg": 62.5, "systolic": 148, "diastolic": 95}
          },
          "attachment_refs": [],
          "created_at": "2026-08-14T09:00:00Z",
          "updated_at": "2026-08-14T09:00:00Z"
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder.aim.decode(APIRecordDTO.self, from: json)
        let record = RecordItem(dto: dto)

        guard case let .checkup(data) = record.structuredData else {
            return XCTFail("应当解成产检记录")
        }
        XCTAssertEqual(data.metrics.weightKg, 62.5)
        XCTAssertEqual(data.metrics.systolic, 148)
        XCTAssertEqual(data.metrics.diastolic, 95)
    }

    /// 表单填的指标要真的发出去。此前保存方向同样丢字段。
    func testMetricsSurviveEncodingToTheServer() throws {
        let data = RecordStructuredData.checkup(CheckupRecordData(
            hospital: "市一医院", examItems: "常规", result: "正常", doctorAdvice: "复查",
            metrics: CheckupMetrics(weightKg: 62.5, systolic: 118, diastolic: 75)))

        let dto = APIRecordStructuredDataDTO(recordData: data)
        let encoded = try JSONSerialization.jsonObject(
            with: try JSONEncoder.aim.encode(dto)) as! [String: Any]

        let metrics = encoded["metrics"] as? [String: Any]
        XCTAssertNotNil(metrics, "指标必须出现在请求体里")
        XCTAssertEqual(metrics?["weight_kg"] as? Double, 62.5)
        XCTAssertEqual(metrics?["systolic"] as? Double, 118)
    }

    /// 解出来的指标要能驱动趋势与「本周关注」。
    func testDecodedMetricsFeedTheTrendAndFocus() throws {
        func checkup(_ day: Int, _ weight: Double, _ systolic: Double) -> RecordItem {
            RecordItem(
                id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
                type: .checkup,
                occurredAt: Calendar.current.date(byAdding: .day, value: -day, to: .now)!,
                visibility: .family, title: nil, content: nil,
                structuredData: .checkup(CheckupRecordData(
                    hospital: "市一医院", examItems: "常规", result: "正常", doctorAdvice: "复查",
                    metrics: CheckupMetrics(weightKg: weight, systolic: systolic, diastolic: 92))),
                attachmentRefs: [], createdAt: .now, updatedAt: .now)
        }
        let records = [checkup(40, 58.0, 145), checkup(5, 62.5, 148)]

        XCTAssertEqual(MetricTrend.weight(from: records)?.points.count, 2)
        XCTAssertNotNil(LibraryFocus.make(from: LibrarySnapshot(records: records)))
    }
}
