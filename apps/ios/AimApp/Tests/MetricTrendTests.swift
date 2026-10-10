import XCTest
@testable import AimApp

@MainActor
final class MetricTrendTests: XCTestCase {
    private func checkup(daysAgo: Int, metrics: CheckupMetrics) -> RecordItem {
        let when = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .checkup, occurredAt: when, visibility: .family,
            title: nil, content: nil,
            structuredData: .checkup(CheckupRecordData(
                hospital: "市一医院", examItems: "常规", result: "正常",
                doctorAdvice: "按时复查", metrics: metrics)),
            attachmentRefs: [], createdAt: when, updatedAt: when
        )
    }

    func testNoCheckupsMeansNoTrend() {
        XCTAssertNil(MetricTrend.weight(from: []))
    }

    /// 一次记录画不出趋势——「变化了多少」至少需要两个点。
    func testASingleReadingHasNoChangeYet() {
        let trend = MetricTrend.weight(from: [checkup(daysAgo: 1, metrics: CheckupMetrics(weightKg: 60))])

        XCTAssertEqual(trend?.points.count, 1)
        XCTAssertNil(trend?.change)
    }

    func testWeightTrendIsOrderedOldestFirst() {
        let records = [
            checkup(daysAgo: 1, metrics: CheckupMetrics(weightKg: 62.5)),
            checkup(daysAgo: 60, metrics: CheckupMetrics(weightKg: 56.3)),
            checkup(daysAgo: 30, metrics: CheckupMetrics(weightKg: 59.0)),
        ]

        let trend = MetricTrend.weight(from: records)

        XCTAssertEqual(trend?.points.map(\.value), [56.3, 59.0, 62.5])
    }

    func testWeightChangeIsMeasuredFromTheFirstReading() {
        let records = [
            checkup(daysAgo: 60, metrics: CheckupMetrics(weightKg: 56.0)),
            checkup(daysAgo: 1, metrics: CheckupMetrics(weightKg: 62.2)),
        ]

        XCTAssertEqual(trend(records)?.change ?? 0, 6.2, accuracy: 0.001)
    }

    /// 没测这项的那几次产检要跳过，不能当成 0 拉低趋势。
    func testCheckupsWithoutThatMetricAreSkipped() {
        let records = [
            checkup(daysAgo: 60, metrics: CheckupMetrics(weightKg: 56.0)),
            checkup(daysAgo: 30, metrics: CheckupMetrics()),
            checkup(daysAgo: 1, metrics: CheckupMetrics(weightKg: 60.0)),
        ]

        XCTAssertEqual(trend(records)?.points.count, 2)
    }

    func testBloodPressureTrendUsesSystolic() {
        let records = [
            checkup(daysAgo: 30, metrics: CheckupMetrics(systolic: 118, diastolic: 75)),
            checkup(daysAgo: 1, metrics: CheckupMetrics(systolic: 134, diastolic: 88)),
        ]

        let trend = MetricTrend.bloodPressure(from: records)

        XCTAssertEqual(trend?.points.map(\.value), [118, 134])
    }

    private func trend(_ records: [RecordItem]) -> MetricTrend? {
        MetricTrend.weight(from: records)
    }

    func testFetalHeartRateAndFundalHeightHaveTrendsWithoutInventingMissingReadings() {
        let records = [
            checkup(daysAgo: 1, metrics: CheckupMetrics(fetalHeartRate: 145, fundalHeightCm: 28)),
            checkup(daysAgo: 7, metrics: CheckupMetrics(weightKg: 60)),
            checkup(daysAgo: 14, metrics: CheckupMetrics(fetalHeartRate: 140, fundalHeightCm: 26)),
        ]
        XCTAssertTrue(MetricKind.available(in: records).contains(.fetalHeartRate))
        XCTAssertTrue(MetricKind.available(in: records).contains(.fundalHeight))
        XCTAssertEqual(MetricKind.fetalHeartRate.trend(in: records)?.points.map(\.value), [140, 145])
        XCTAssertEqual(MetricKind.fundalHeight.trend(in: records)?.points.map(\.value), [26, 28])
        XCTAssertEqual(MetricKind.fetalHeartRate.unit, "次/分")
        XCTAssertEqual(MetricKind.fundalHeight.unit, "cm")
    }
}
