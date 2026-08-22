import Foundation

/// 一次产检里可计算的指标。全部可选——不是每次产检都测所有项。
struct CheckupMetrics: Codable, Equatable, Sendable {
    var weightKg: Double?
    var systolic: Double?
    var diastolic: Double?
    var fastingGlucose: Double?
    var hemoglobin: Double?

    var isEmpty: Bool {
        weightKg == nil && systolic == nil && diastolic == nil
            && fastingGlucose == nil && hemoglobin == nil
    }

    enum CodingKeys: String, CodingKey {
        case weightKg = "weight_kg"
        case systolic, diastolic
        case fastingGlucose = "fasting_glucose"
        case hemoglobin
    }
}

struct MetricPoint: Equatable, Sendable {
    let date: Date
    let value: Double
}

/// 一项指标随时间的变化。用于资料库卡片上的迷你趋势条。
struct MetricTrend: Equatable, Sendable {
    let unit: String
    /// 按时间升序——趋势要从左往右读。
    let points: [MetricPoint]

    /// 相对第一次读数的变化。只有一个点时为 nil：一次记录画不出趋势。
    var change: Double? {
        guard let first = points.first, let last = points.last, points.count > 1 else { return nil }
        return last.value - first.value
    }

    var latest: Double? { points.last?.value }

    static func weight(from records: [RecordItem]) -> MetricTrend? {
        make(from: records, unit: "kg") { $0.weightKg }
    }

    /// 血压用收缩压画趋势——它是孕期最常被关注的那个数。
    static func bloodPressure(from records: [RecordItem]) -> MetricTrend? {
        make(from: records, unit: "mmHg") { $0.systolic }
    }

    private static func make(
        from records: [RecordItem],
        unit: String,
        pick: (CheckupMetrics) -> Double?
    ) -> MetricTrend? {
        let points = records
            .compactMap { record -> MetricPoint? in
                guard case let .checkup(data) = record.structuredData,
                      // 没测这项的产检要跳过，不能当成 0 拉低趋势。
                      let value = pick(data.metrics) else { return nil }
                return MetricPoint(date: record.occurredAt, value: value)
            }
            .sorted { $0.date < $1.date }
        return points.isEmpty ? nil : MetricTrend(unit: unit, points: points)
    }
}
