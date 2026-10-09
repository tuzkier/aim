import Foundation

/// 一次「数到 10 次」胎动计数。
///
/// 纯数据、不碰计时器：所有判断都以开始时间和传入的「现在」计算。
/// App 被系统挂起或杀掉后，从本地恢复同一个值就能接着算，计时也不会停。
struct FetalMovementCounter: Codable, Equatable, Sendable {
    static let target = 10
    static let window: TimeInterval = 2 * 60 * 60
    /// 一阵连续的动只算一次；这里只防手抖连点，不做更长的自动合并——
    /// 规则不透明，用户会困惑数字为什么没变。
    static let defaultDedupeInterval: TimeInterval = 3

    enum TapResult: Equatable, Sendable { case counted, ignored, reachedTarget, expired }

    let startedAt: Date
    let dedupeInterval: TimeInterval
    private(set) var taps: [TimeInterval] = []

    init(startedAt: Date, dedupeInterval: TimeInterval = Self.defaultDedupeInterval) {
        self.startedAt = startedAt
        self.dedupeInterval = dedupeInterval
    }

    var count: Int { taps.count }

    func elapsed(at now: Date) -> TimeInterval { max(0, now.timeIntervalSince(startedAt)) }

    func isExpired(at now: Date) -> Bool { count < Self.target && elapsed(at: now) >= Self.window }

    mutating func tap(at now: Date) -> TapResult {
        guard count < Self.target else { return .reachedTarget }
        if isExpired(at: now) { return .expired }
        let offset = elapsed(at: now)
        if let last = taps.last, offset - last < dedupeInterval { return .ignored }
        taps.append(offset)
        return count == Self.target ? .reachedTarget : .counted
    }

    func result(at now: Date) -> FetalMovementResult {
        let seconds = taps.map { Int($0.rounded(.down)) }
        if count >= Self.target {
            return FetalMovementResult(
                startedAt: startedAt, durationSeconds: Int(taps[Self.target - 1].rounded(.up)),
                count: count, outcome: .reached, taps: seconds)
        }
        if isExpired(at: now) {
            return FetalMovementResult(
                startedAt: startedAt, durationSeconds: Int(Self.window),
                count: count, outcome: .under, taps: seconds)
        }
        // 系统时钟回拨后 elapsed 可能短于最后一次点击；用时至少盖住它，否则后端校验不过。
        return FetalMovementResult(
            startedAt: startedAt,
            durationSeconds: max(Int(elapsed(at: now).rounded(.down)), seconds.last ?? 0),
            count: count, outcome: .stopped, taps: seconds)
    }
}

struct FetalMovementResult: Codable, Equatable, Sendable {
    let startedAt: Date
    let durationSeconds: Int
    let count: Int
    let outcome: FetalMovementOutcome
    let taps: [Int]

    var recordData: FetalMovementRecordData {
        FetalMovementRecordData(
            durationSeconds: durationSeconds, count: count, target: FetalMovementCounter.target,
            outcome: outcome, taps: taps)
    }

    /// 家庭动态直接显示它：「爸爸 记了「数胎动 10 次 · 32 分钟」」。
    var title: String { "数胎动 " + FetalMovementFormat.summary(recordData) }

    var draft: RecordDraft {
        RecordDraft(
            type: .fetalMovement, occurredAt: startedAt, visibility: .family,
            title: title, content: nil, structuredData: .fetalMovement(recordData))
    }
}

/// 档案里的一次计数。
struct FetalMovementSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let data: FetalMovementRecordData

    init(id: UUID, startedAt: Date, data: FetalMovementRecordData) {
        self.id = id
        self.startedAt = startedAt
        self.data = data
    }

    init?(record: RecordItem) {
        guard case let .fetalMovement(data) = record.structuredData else { return nil }
        self.init(id: record.id, startedAt: record.occurredAt, data: data)
    }
}

struct FetalMovementDay: Equatable, Sendable {
    let date: Date
    /// 当天第一次数到 10 次的用时；没有完成的计数为 nil。
    let reachedSeconds: Int?
    let hadUnder: Bool
}

enum FetalMovementInsights {
    static let baselineWindow = 7
    static let baselineMinimum = 3
    static let slowFloorSeconds = 30 * 60

    /// 「平时」：最近 7 次数到 10 次的用时中位数，至少 3 次才算。
    static func baselineSeconds(_ sessions: [FetalMovementSession]) -> Int? {
        let recent = sessions
            .filter { $0.data.outcome == .reached }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(baselineWindow)
            .map(\.data.durationSeconds)
            .sorted()
        guard recent.count >= baselineMinimum else { return nil }
        let middle = recent.count / 2
        return recent.count.isMultiple(of: 2)
            ? (recent[middle - 1] + recent[middle]) / 2
            : recent[middle]
    }

    /// 数到 10 次的用时翻倍，大致相当于胎动比平时减少一半。
    static func isSlow(durationSeconds: Int, baselineSeconds: Int?) -> Bool {
        guard let baselineSeconds else { return false }
        return durationSeconds > baselineSeconds * 2 && durationSeconds > slowFloorSeconds
    }

    static func latest(
        onDayOf now: Date, in sessions: [FetalMovementSession], calendar: Calendar = .current
    ) -> FetalMovementSession? {
        sessions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: now) }
            .max { $0.startedAt < $1.startedAt }
    }

    /// 最近 `days` 天（含今天），从早到晚。
    static func dailyTrend(
        _ sessions: [FetalMovementSession], days: Int = 14, now: Date, calendar: Calendar = .current
    ) -> [FetalMovementDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let sameDay = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
            let firstReached = sameDay
                .filter { $0.data.outcome == .reached }
                .min { $0.startedAt < $1.startedAt }
            return FetalMovementDay(
                date: day,
                reachedSeconds: firstReached?.data.durationSeconds,
                hadUnder: sameDay.contains { $0.data.outcome == .under })
        }
    }
}
