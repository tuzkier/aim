import Foundation

struct BabyProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let pregnancyID: UUID
    let familyID: UUID
    let name: String
    let birthDate: Date
    let sex: String
    let birthWeightGrams: Int?
    enum CodingKeys: String, CodingKey {
        case id, name, sex
        case pregnancyID = "pregnancy_id", familyID = "family_id"
        case birthDate = "birth_date", birthWeightGrams = "birth_weight_grams"
    }
    func daysOld(now: Date = .now) -> Int {
        max(0, EmotionalSchedule.calendar.dateComponents([.day], from: EmotionalSchedule.calendar.startOfDay(for: birthDate),
                                                         to: EmotionalSchedule.calendar.startOfDay(for: now)).day ?? 0)
    }
}

struct BabyDraft: Equatable, Sendable {
    var name: String = "宝宝"
    var birthDate: Date
    var sex: String = "unknown"
    var birthWeightGrams: Int?
}

struct BirthSnapshot: Sendable {
    let pregnancy: PregnancySummary
    let babies: [BabyProfile]
}

enum BabyCareKind: String, CaseIterable, Sendable { case feeding, diaper, sleep
    var title: String {
        switch self { case .feeding: "喂养"; case .diaper: "尿布"; case .sleep: "睡眠" }
    }
    var recordType: RecordType {
        switch self { case .feeding: .feeding; case .diaper: .diaper; case .sleep: .sleep }
    }
}

struct BabyCareRecordData: Equatable, Sendable {
    let babyID: UUID
    var mode: String?
    var volumeMl: Double?
    var durationMinutes: Int?
    var side: String?
    var diaperKind: String?
    var endedAt: Date?
    var durationSeconds: Int?

    var feedingLabel: String {
        switch mode {
        case "breast": "母乳亲喂"
        case "expressed": "瓶喂母乳"
        case "formula": "配方奶"
        case "mixed": "混合喂养"
        default: "方式未填"
        }
    }
    var diaperLabel: String {
        switch diaperKind { case "wet": "湿尿布"; case "dirty": "便尿布"; case "both": "尿和便都有"; case "dry": "干尿布"; default: "尿布记录" }
    }
    static func amount(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
}

extension RecordItem {
    var babyCare: BabyCareRecordData? {
        switch structuredData { case let .feeding(data), let .diaper(data), let .sleep(data): data; default: nil }
    }
}

struct BabyDaySummary: Equatable {
    var feedingCount = 0
    var knownVolumeMl: Double?
    var unmeasuredFeeds = 0
    var diaperCount = 0
    var wetCount = 0
    var dirtyCount = 0
    var sleepSeconds = 0

    static func calculate(records: [RecordItem], babyID: UUID, now: Date) -> Self {
        let calendar = EmotionalSchedule.calendar
        let day = calendar.startOfDay(for: now)
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        var result = Self()
        var spans: [(Date, Date)] = []
        for record in records {
            guard let data = record.babyCare, data.babyID == babyID else { continue }
            if record.type == .sleep, let end = data.endedAt {
                let start = max(day, record.occurredAt), finish = min(next, end)
                if finish > start { spans.append((start, finish)) }
                continue
            }
            guard record.occurredAt >= day, record.occurredAt < next else { continue }
            if record.type == .feeding {
                result.feedingCount += 1
                if let ml = data.volumeMl { result.knownVolumeMl = (result.knownVolumeMl ?? 0) + ml }
                else { result.unmeasuredFeeds += 1 }
            } else if record.type == .diaper {
                result.diaperCount += 1
                if data.diaperKind == "wet" || data.diaperKind == "both" { result.wetCount += 1 }
                if data.diaperKind == "dirty" || data.diaperKind == "both" { result.dirtyCount += 1 }
            }
        }
        // 重叠日志不把同一睡眠算两次；跨午夜只算当天交集。
        var merged: [(Date, Date)] = []
        for span in spans.sorted(by: { $0.0 < $1.0 }) {
            if let last = merged.last, span.0 <= last.1 { merged[merged.count - 1].1 = max(last.1, span.1) }
            else { merged.append(span) }
        }
        result.sleepSeconds = merged.reduce(0) { $0 + Int($1.1.timeIntervalSince($1.0)) }
        return result
    }
}

struct PostpartumContent: Decodable, Sendable {
    struct Item: Decodable, Identifiable, Sendable {
        let id: String
        let title: String
        let summary: String
        var months: Int?
        var days: Int?
        var age: String?
    }
    let care: [Item]
    let documents: [Item]
    let vaccines: [Item]
    let vaccineNotice: String
    let vaccineSourceURL: String
    let careSourceURL: String
    let documentsSourceURL: String
    static func load() -> Self? {
        guard let url = Bundle.main.url(forResource: "care", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

enum PostpartumCalendar {
    static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = EmotionalSchedule.calendar
        formatter.timeZone = EmotionalSchedule.calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }
    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = EmotionalSchedule.calendar
        formatter.timeZone = EmotionalSchedule.calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func addingMonths(_ count: Int, to date: Date) -> Date {
        EmotionalSchedule.calendar.date(byAdding: .month, value: count, to: date)!
    }
}
