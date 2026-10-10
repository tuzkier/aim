import Foundation

/// 一次产检里可计算的指标。全部可选——不是每次产检都测所有项。
struct CheckupMetrics: Codable, Equatable, Sendable {
    var weightKg: Double?
    var systolic: Double?
    var diastolic: Double?
    var fastingGlucose: Double?
    var hemoglobin: Double?
    /// 胎心，次/分。
    var fetalHeartRate: Double?
    /// 宫高，厘米。
    var fundalHeightCm: Double?

    /// 判断要不要发 metrics。新增指标必须算进来，否则只测了胎心的报告会被当成没填。
    var isEmpty: Bool {
        weightKg == nil && systolic == nil && diastolic == nil
            && fastingGlucose == nil && hemoglobin == nil
            && fetalHeartRate == nil && fundalHeightCm == nil
    }

    enum CodingKeys: String, CodingKey {
        case weightKg = "weight_kg"
        case systolic, diastolic
        case fastingGlucose = "fasting_glucose"
        case hemoglobin
        case fetalHeartRate = "fetal_heart_rate"
        case fundalHeightCm = "fundal_height_cm"
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

/// 可以画趋势的指标种类。
///
/// 「只列出真有数据的」是这里的关键：空着的切换项点进去是一片空白，等于骗人。
enum MetricKind: String, CaseIterable, Identifiable, Sendable {
    case weight
    case bloodPressure
    case fastingGlucose
    case hemoglobin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: "体重"
        case .bloodPressure: "血压"
        case .fastingGlucose: "空腹血糖"
        case .hemoglobin: "血红蛋白"
        }
    }

    /// 单位跟着指标走，否则「62 mmHg」这种显示会误导。
    var unit: String {
        switch self {
        case .weight: "kg"
        case .bloodPressure: "mmHg"
        case .fastingGlucose: "mmol/L"
        case .hemoglobin: "g/L"
        }
    }

    /// 血压用收缩压画趋势——它是孕期最常被关注的那个数。
    private var pick: @Sendable (CheckupMetrics) -> Double? {
        switch self {
        case .weight: { $0.weightKg }
        case .bloodPressure: { $0.systolic }
        case .fastingGlucose: { $0.fastingGlucose }
        case .hemoglobin: { $0.hemoglobin }
        }
    }

    func trend(in records: [RecordItem]) -> MetricTrend? {
        let points = records
            .compactMap { record -> MetricPoint? in
                guard case let .checkup(data) = record.structuredData,
                      let value = pick(data.metrics) else { return nil }
                return MetricPoint(date: record.occurredAt, value: value)
            }
            .sorted { $0.date < $1.date }
        return points.isEmpty ? nil : MetricTrend(unit: unit, points: points)
    }

    static func available(in records: [RecordItem]) -> [MetricKind] {
        allCases.filter { $0.trend(in: records) != nil }
    }
}
