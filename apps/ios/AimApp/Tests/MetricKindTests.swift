import XCTest
@testable import AimApp

@MainActor
final class MetricKindTests: XCTestCase {
    private func checkup(_ daysAgo: Int, _ metrics: CheckupMetrics) -> RecordItem {
        let when = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .checkup, occurredAt: when, visibility: .family, title: nil, content: nil,
            structuredData: .checkup(CheckupRecordData(
                hospital: "市一", examItems: "常规", result: "正常",
                doctorAdvice: "复查", metrics: metrics)),
            attachmentRefs: [], createdAt: when, updatedAt: when)
    }

    /// 只列出真有数据的指标。空着的切换项点进去是一片空白，等于骗人。
    func testOnlyMetricsWithDataAreOffered() {
        let records = [
            checkup(30, CheckupMetrics(weightKg: 58, systolic: 118, diastolic: 75)),
            checkup(1, CheckupMetrics(weightKg: 62)),
        ]

        let kinds = MetricKind.available(in: records)

        XCTAssertTrue(kinds.contains(.weight))
        XCTAssertTrue(kinds.contains(.bloodPressure))
        XCTAssertFalse(kinds.contains(.fastingGlucose), "没测过的指标不该出现在切换里")
    }

    func testNoCheckupsMeansNoMetrics() {
        XCTAssertTrue(MetricKind.available(in: []).isEmpty)
    }

    func testEachKindBuildsItsOwnTrend() {
        let records = [
            checkup(30, CheckupMetrics(weightKg: 58, systolic: 118, diastolic: 75)),
            checkup(1, CheckupMetrics(weightKg: 62, systolic: 124, diastolic: 80)),
        ]

        XCTAssertEqual(MetricKind.weight.trend(in: records)?.points.map(\.value), [58, 62])
        XCTAssertEqual(MetricKind.bloodPressure.trend(in: records)?.points.map(\.value), [118, 124])
    }

    /// 单位要跟着指标走，否则「62 mmHg」这种显示会误导。
    func testUnitsMatchTheMetric() {
        XCTAssertEqual(MetricKind.weight.unit, "kg")
        XCTAssertEqual(MetricKind.bloodPressure.unit, "mmHg")
    }
}
