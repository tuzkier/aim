import Foundation

/// 某一周的孕周内容：水果比喻、身长体重、宝宝、妈妈、建议。来自内容库，按周写死，不让 AI 现场生成。
struct WeekContent: Codable, Equatable, Sendable {
    let week: Int
    let fruit: String
    let fruitName: String
    let lengthCm: Double?
    let weightG: Double?
    let baby: String
    let mom: String
    let tips: [String]

    enum CodingKeys: String, CodingKey {
        case week, fruit, baby, mom, tips
        case fruitName = "fruit_name"
        case lengthCm = "length_cm"
        case weightG = "weight_g"
    }

    /// 「约 41 厘米 · 1.5 公斤」；早期没有体重时只写身长，都没有时为 nil。
    var sizeText: String? {
        var parts: [String] = []
        if let lengthCm { parts.append("约 \(lengthCm.formatted(.number.precision(.fractionLength(0...1)))) 厘米") }
        if let weightG {
            parts.append(weightG >= 1000
                ? "\((weightG / 1000).formatted(.number.precision(.fractionLength(1)))) 公斤"
                : "\(Int(weightG.rounded())) 克")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// 第 4–42 周的全部内容。
struct WeeklyContentBook: Codable, Equatable, Sendable {
    let source: String
    let sourceURL: String
    let reviewedAt: String
    let weeks: [WeekContent]

    enum CodingKeys: String, CodingKey {
        case source, weeks
        case sourceURL = "source_url"
        case reviewedAt = "reviewed_at"
    }

    static let firstWeek = 4
    static let lastWeek = 42

    /// 4 周以前：宝宝刚开始发育，不给身长体重。
    static let earlyFallback = WeekContent(
        week: 3, fruit: "🌱", fruitName: "一颗小种子", lengthCm: nil, weightG: nil,
        baby: "宝宝刚开始发育，一切才刚刚开始。",
        mom: "可能还没有明显感觉，按时做早孕检查。",
        tips: ["每天补充叶酸", "按医生安排做早孕检查"])

    /// 4 周以前用通用内容；42 周以后按第 42 周。
    func content(forWeek week: Int) -> WeekContent {
        guard week >= Self.firstWeek else { return Self.earlyFallback }
        let clamped = min(week, Self.lastWeek)
        return weeks.first { $0.week == clamped } ?? Self.earlyFallback
    }
}

/// 孕早、中、晚期。与待办页时间轴的划分一致。
enum PregnancyStage: Equatable, Sendable {
    case early, middle, late

    init(weeks: Int) {
        if weeks <= 13 { self = .early } else if weeks <= 27 { self = .middle } else { self = .late }
    }

    var title: String {
        switch self {
        case .early: "孕早期"
        case .middle: "孕中期"
        case .late: "孕晚期"
        }
    }

    /// 阶段起止（天）：孕早期 0–14 周，孕中期 14–28 周，孕晚期 28–40 周。
    var dayRange: Range<Int> {
        switch self {
        case .early: 0..<(14 * 7)
        case .middle: (14 * 7)..<(28 * 7)
        case .late: (28 * 7)..<(40 * 7)
        }
    }
}

/// 孕期走到哪了：整体进度、所在阶段及阶段内进度、距预产期天数。
struct PregnancyProgress: Equatable, Sendable {
    static let totalDays = 280

    let elapsedDays: Int

    init(weeks: Int, days: Int) {
        elapsedDays = weeks * 7 + days
    }

    var weeks: Int { elapsedDays / 7 }
    var fraction: Double { min(1, max(0, Double(elapsedDays) / Double(Self.totalDays))) }
    var stage: PregnancyStage { PregnancyStage(weeks: weeks) }

    var stageFraction: Double {
        let range = stage.dayRange
        return min(1, max(0, Double(elapsedDays - range.lowerBound) / Double(range.count)))
    }

    /// 距预产期还有几天；过了预产期为负。
    var daysLeft: Int { Self.totalDays - elapsedDays }
}

/// 孕周内容的本地缓存：启动先用缓存显示，后台再刷新。
struct WeeklyContentCache: Sendable {
    let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = base.appendingPathComponent("weekly-content.json")
    }

    func load() -> WeeklyContentBook? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WeeklyContentBook.self, from: data)
    }

    func save(_ book: WeeklyContentBook) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(book).write(to: fileURL, options: .atomic)
    }
}
