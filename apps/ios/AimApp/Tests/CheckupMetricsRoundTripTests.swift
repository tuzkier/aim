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

    private func record(type: String, structuredData: String) throws -> RecordItem {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "pregnancy_id": "22222222-2222-2222-2222-222222222222",
          "family_id": "33333333-3333-3333-3333-333333333333",
          "author_account_id": "44444444-4444-4444-4444-444444444444",
          "type": "\(type)",
          "occurred_at": "2026-10-03T01:00:00Z",
          "visibility": "family",
          "title": null,
          "content": null,
          "structured_data": \(structuredData),
          "attachment_refs": [],
          "created_at": "2026-10-03T01:00:00Z",
          "updated_at": "2026-10-03T01:00:00Z"
        }
        """.data(using: .utf8)!
        return RecordItem(dto: try JSONDecoder.aim.decode(APIRecordDTO.self, from: json))
    }

    private func encoded(_ data: RecordStructuredData) throws -> [String: Any] {
        let body = try JSONEncoder.aim.encode(APIRecordStructuredDataDTO(recordData: data))
        return try JSONSerialization.jsonObject(with: body) as! [String: Any]
    }

    /// 四段文字都改成可选了。只有指标的报告此前解成 `.unknown`，详情页和趋势都看不到它。
    func testCheckupWithOnlyMetricsIsStillACheckup() throws {
        let item = try record(
            type: "checkup",
            structuredData: #"{"metrics":{"fetal_heart_rate":142,"fundal_height_cm":28.5}}"#)

        guard case let .checkup(data) = item.structuredData else {
            return XCTFail("只有指标也应当解成产检记录，实际：\(item.structuredData)")
        }
        XCTAssertNil(data.hospital)
        XCTAssertNil(data.examItems)
        XCTAssertNil(data.result)
        XCTAssertNil(data.doctorAdvice)
        XCTAssertEqual(data.metrics.fetalHeartRate, 142)
        XCTAssertEqual(data.metrics.fundalHeightCm, 28.5)
        XCTAssertTrue(data.otherItems.isEmpty)
    }

    /// 只测了胎心、宫高的报告，指标也要发出去——此前 isEmpty 只看五项，会把它们当成没填丢掉。
    func testNewMetricsAloneAreStillSent() throws {
        let body = try encoded(.checkup(CheckupRecordData(
            hospital: nil, examItems: nil, result: nil, doctorAdvice: nil,
            metrics: CheckupMetrics(fetalHeartRate: 140, fundalHeightCm: 30), otherItems: [])))

        let metrics = body["metrics"] as? [String: Any]
        XCTAssertEqual(metrics?["fetal_heart_rate"] as? Double, 140)
        XCTAssertEqual(metrics?["fundal_height_cm"] as? Double, 30)
    }

    /// 没填的文字段不发，而不是发空串。
    func testMissingTextSectionsAreLeftOut() throws {
        let body = try encoded(.checkup(CheckupRecordData(
            hospital: "市一医院", examItems: nil, result: nil, doctorAdvice: nil,
            metrics: CheckupMetrics(weightKg: 60), otherItems: [])))

        XCTAssertEqual(body["hospital"] as? String, "市一医院")
        XCTAssertNil(body["exam_items"])
        XCTAssertNil(body["result"])
        XCTAssertNil(body["doctor_advice"])
        XCTAssertNil(body["other_items"], "没有其他化验项就不发这个字段")
    }

    /// 其他化验项要完整往返：编辑旧报告时整段 structured_data 会被替换，丢一个字段就是丢数据。
    func testOtherItemsSurviveARoundTrip() throws {
        let item = try record(type: "checkup", structuredData: """
        {"result":"尿蛋白弱阳性",
         "other_items":[
           {"name":"尿蛋白","value":"+-","reference":"阴性","flag":"abnormal"},
           {"name":"白细胞","value":"12.1","unit":"10^9/L","reference":"3.5-9.5","flag":"high"},
           {"name":"血小板","value":"210","unit":"10^9/L"}
         ]}
        """)

        guard case let .checkup(data) = item.structuredData else { return XCTFail("应当是产检记录") }
        XCTAssertEqual(data.otherItems, [
            CheckupOtherItem(name: "尿蛋白", value: "+-", unit: nil, reference: "阴性", flag: .abnormal),
            CheckupOtherItem(name: "白细胞", value: "12.1", unit: "10^9/L", reference: "3.5-9.5", flag: .high),
            CheckupOtherItem(name: "血小板", value: "210", unit: "10^9/L", reference: nil, flag: nil),
        ])

        let body = try encoded(item.structuredData)
        let items = body["other_items"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 3)
        XCTAssertEqual(items?[0]["flag"] as? String, "abnormal")
        XCTAssertEqual(items?[1]["unit"] as? String, "10^9/L")
        XCTAssertNil(items?[2]["flag"], "没有标记就不发 flag")
        XCTAssertNil(items?[2]["reference"])
    }

    /// 服务端以后多一种标记，不能让整份记录列表解不出来。
    func testUnknownFlagDecodesAsNoFlag() throws {
        let item = try record(type: "checkup", structuredData: """
        {"other_items":[{"name":"尿糖","value":"+","flag":"critical"}]}
        """)

        guard case let .checkup(data) = item.structuredData else { return XCTFail("应当是产检记录") }
        XCTAssertEqual(data.otherItems.first?.name, "尿糖")
        XCTAssertNil(data.otherItems.first?.flag)
    }

    /// 从报告攒出来的问题指回报告。服务端只认小写标准写法，发回去也必须是小写。
    func testQuestionReportIDSurvivesARoundTripInLowercase() throws {
        let reportID = "a1b2c3d4-e5f6-4789-8abc-def012345678"
        let item = try record(
            type: "question", structuredData: #"{"answered":false,"report_id":"\#(reportID)"}"#)

        guard case let .question(data) = item.structuredData else { return XCTFail("应当是问题记录") }
        XCTAssertEqual(data.reportID, UUID(uuidString: reportID))

        let body = try encoded(item.structuredData)
        XCTAssertEqual(body["report_id"] as? String, reportID)
    }

    func testManualQuestionsHaveNoReportID() throws {
        let item = try record(type: "question", structuredData: #"{"answered":false}"#)

        guard case let .question(data) = item.structuredData else { return XCTFail("应当是问题记录") }
        XCTAssertNil(data.reportID)
        XCTAssertNil(try encoded(item.structuredData)["report_id"])
    }

    /// 表单回填一份 AIM 建的报告再保存：其他化验项与胎心都还在；空文字段传 nil。
    func testEditingAReportKeepsOtherItemsAndFetalHeartRate() {
        let original = CheckupRecordData(
            hospital: "市一医院", examItems: nil, result: "尿蛋白弱阳性", doctorAdvice: nil,
            metrics: CheckupMetrics(weightKg: 60, fetalHeartRate: 145),
            otherItems: [CheckupOtherItem(name: "尿蛋白", value: "+-", reference: "阴性", flag: .abnormal)])

        var form = CheckupForm(data: original)
        form.hospital = " 市一医院 "
        form.doctorAdvice = "  "
        form.metrics[.weight] = "61"
        let draft = form.draft

        XCTAssertEqual(draft.hospital, "市一医院")
        XCTAssertNil(draft.examItems)
        XCTAssertNil(draft.doctorAdvice)
        XCTAssertEqual(draft.metrics.weightKg, 61)
        XCTAssertEqual(draft.metrics.fetalHeartRate, 145)
        XCTAssertEqual(draft.otherItems, original.otherItems)
    }

    func testANewReportStartsWithoutOtherItems() {
        var form = CheckupForm(suggestedExamItems: "常规")
        form.result = ""
        let draft = form.draft

        XCTAssertEqual(draft.examItems, "常规")
        XCTAssertNil(draft.hospital)
        XCTAssertTrue(draft.metrics.isEmpty)
        XCTAssertTrue(draft.otherItems.isEmpty)
    }
}
