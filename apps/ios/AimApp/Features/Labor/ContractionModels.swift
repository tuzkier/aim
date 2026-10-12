import Foundation

/// 一次宫缩计时：每次宫缩的开始与结束时刻。
///
/// 纯数据、不碰计时器：所有判断以时间戳和传入的「现在」计算。
/// App 被挂起或杀掉后，从本地恢复同一个值就能接着算。
struct ContractionTimer: Codable, Equatable, Sendable {
    struct Span: Codable, Equatable, Sendable {
        let start: Date
        var end: Date?
    }

    /// 单次宫缩最长记 10 分钟：再长多半是忘了按结束，后端也不收。
    static let maxDuration: TimeInterval = 600
    /// 超过 3 分钟还没结束要提示「持续剧痛不缓解请立即去医院」。
    static let longRunning: TimeInterval = 180
    /// 20 分钟没有宫缩，实时档位回落。
    static let quietAfter: TimeInterval = 1200
    /// 最后一次结束超过 6 小时还没保存，先让用户决定保存还是丢弃。
    static let staleAfter: TimeInterval = 21_600
    /// 不到 1 秒的开始或结束都当误触。
    static let minimumGap: TimeInterval = 1

    private(set) var spans: [Span] = []

    init() {}

    var startedAt: Date? { spans.first?.start }
    var isContracting: Bool { spans.last.map { $0.end == nil } ?? false }
    var completed: [Span] { spans.filter { $0.end != nil } }
    var lastEnd: Date? { completed.last?.end }

    enum ToggleResult: Equatable, Sendable { case began, ended, ignored }

    mutating func toggle(at now: Date) -> ToggleResult {
        if isContracting, let start = spans.last?.start {
            guard now.timeIntervalSince(start) >= Self.minimumGap else {
                spans.removeLast()
                return .ignored
            }
            spans[spans.count - 1].end = min(now, start + Self.maxDuration)
            return .ended
        }
        if let lastEnd, now.timeIntervalSince(lastEnd) < Self.minimumGap { return .ignored }
        spans.append(Span(start: now, end: nil))
        return .began
    }

    /// 误按了：宫缩中就取消这一次，否则删掉最后一次。
    mutating func removeLast() {
        guard !spans.isEmpty else { return }
        spans.removeLast()
    }

    /// 宫缩中被系统杀掉、很久才回来：超过 10 分钟的截断为 10 分钟并结束。
    mutating func capRunning(at now: Date) {
        guard isContracting, let start = spans.last?.start,
              now.timeIntervalSince(start) > Self.maxDuration else { return }
        spans[spans.count - 1].end = start + Self.maxDuration
    }

    func isStale(at now: Date) -> Bool {
        guard !isContracting, let lastEnd else { return false }
        return now.timeIntervalSince(lastEnd) > Self.staleAfter
    }

    /// 存档用：只含已结束的宫缩。开始与结束都按距第一次开始的整秒向下取整，
    /// 持续 = 结束秒 − 开始秒（至少 1），这样取整后也不会和下一次重叠。
    func entries() -> [ContractionEntry] {
        guard let origin = completed.first?.start else { return [] }
        return completed.compactMap { span in
            guard let end = span.end else { return nil }
            let start = Int(span.start.timeIntervalSince(origin).rounded(.down))
            let finish = Int(end.timeIntervalSince(origin).rounded(.down))
            return ContractionEntry(start: start, duration: min(max(1, finish - start), Int(Self.maxDuration)))
        }
    }
}

enum ContractionStage: Equatable, Sendable { case early, approaching, go, pretermAlert }

struct ContractionStatus: Equatable, Sendable {
    let stage: ContractionStage
    let summary: ContractionSummary?
    let quietMinutes: Int?
    let runningSeconds: Int?

    var isLongRunning: Bool { (runningSeconds ?? 0) > Int(ContractionTimer.longRunning) }
}

/// 5-1-1 档位。与服务端 `aim_api.contexts.records.domain.contraction` 同一套规则，
/// 两边共用 contracts/fixtures/contraction-summary-vectors.json 的测试向量。
enum ContractionMath {
    static let goMaxInterval: Double = 300
    static let goMinDuration: Double = 50
    static let goMinSpan = 3300
    static let approachingMinCount = 4
    static let approachingMaxInterval: Double = 420
    static let pretermWeeks = 37

    static func summary(_ entries: [ContractionEntry]) -> ContractionSummary {
        guard let latest = entries.last?.start else {
            return ContractionSummary(count: 0, lastHourCount: 0, avgIntervalSeconds: nil,
                                      avgDurationSeconds: 0, pattern: .early)
        }
        let hour = entries.filter { $0.start >= latest - 3600 }
        let half = entries.filter { $0.start >= latest - 1800 }
        let hourInterval = averageInterval(hour.map(\.start))
        let hourDuration = Double(hour.map(\.duration).reduce(0, +)) / Double(hour.count)
        let halfInterval = averageInterval(half.map(\.start))

        var pattern = ContractionPattern.early
        if let hourInterval, hourInterval <= goMaxInterval, hourDuration >= goMinDuration,
           let first = hour.first?.start, latest - first >= goMinSpan {
            pattern = .go
        } else if half.count >= approachingMinCount, let halfInterval, halfInterval <= approachingMaxInterval {
            pattern = .approaching
        }
        return ContractionSummary(
            count: entries.count, lastHourCount: hour.count,
            avgIntervalSeconds: hourInterval.map { Int($0.rounded()) },
            avgDurationSeconds: Int(hourDuration.rounded()), pattern: pattern)
    }

    static func status(_ timer: ContractionTimer, at now: Date, weeks: Int?) -> ContractionStatus {
        let entries = timer.entries()
        let summary = entries.isEmpty ? nil : summary(entries)
        let running = timer.isContracting
            ? timer.spans.last.map { max(0, Int(now.timeIntervalSince($0.start).rounded(.down))) }
            : nil

        // 早产：以现在为准数最近 20 / 60 分钟开始的宫缩（含正在进行的这一次）。
        if let weeks, weeks < pretermWeeks {
            let starts = timer.spans.map(\.start)
            let inTwenty = starts.filter { now.timeIntervalSince($0) <= 1200 }.count
            let inHour = starts.filter { now.timeIntervalSince($0) <= 3600 }.count
            if inTwenty >= 4 || inHour >= 8 {
                return ContractionStatus(stage: .pretermAlert, summary: summary, quietMinutes: nil, runningSeconds: running)
            }
        }

        // 停顿回落：空档不在窗口的平均间隔里，档位不会自己回落，单独判断。
        if !timer.isContracting, let lastEnd = timer.lastEnd {
            let quiet = now.timeIntervalSince(lastEnd)
            if quiet > ContractionTimer.quietAfter {
                return ContractionStatus(stage: .early, summary: summary,
                                         quietMinutes: Int(quiet / 60), runningSeconds: nil)
            }
        }

        let stage: ContractionStage = switch summary?.pattern {
        case .go: .go
        case .approaching: .approaching
        case .early, .none: .early
        }
        return ContractionStatus(stage: stage, summary: summary, quietMinutes: nil, runningSeconds: running)
    }

    private static func averageInterval(_ starts: [Int]) -> Double? {
        guard starts.count >= 2, let first = starts.first, let last = starts.last else { return nil }
        return Double(last - first) / Double(starts.count - 1)
    }
}

/// 结束计时后待保存的一次计时。`id` 只用于本地队列去重。
struct ContractionResult: Codable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let entries: [ContractionEntry]

    var recordData: ContractionRecordData { ContractionRecordData(contractions: entries, summary: nil) }

    /// 家庭动态直接显示它：「爸爸 记了「宫缩计时 · 14 次 · 约 4 分 50 秒一次」」。
    var title: String {
        "宫缩计时 · " + ContractionFormat.summary(
            ContractionRecordData(contractions: entries, summary: ContractionMath.summary(entries)))
    }

    var draft: RecordDraft {
        RecordDraft(type: .contraction, occurredAt: startedAt, visibility: .family,
                    title: title, content: nil, structuredData: .contraction(recordData))
    }
}

/// 档案里的一次宫缩计时。
struct ContractionSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let data: ContractionRecordData

    init?(record: RecordItem) {
        guard case let .contraction(data) = record.structuredData else { return nil }
        id = record.id
        startedAt = record.occurredAt
        self.data = data
    }
}

enum ContractionFormat {
    /// 「45 秒」「4 分 50 秒」「5 分钟」。
    static func seconds(_ value: Int) -> String {
        guard value >= 60 else { return "\(value) 秒" }
        let minutes = value / 60, rest = value % 60
        return rest == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(rest) 秒"
    }

    /// 「14 次 · 约 4 分 50 秒一次」；只有一次时只说次数。
    static func summary(_ data: ContractionRecordData) -> String {
        let summary = data.summary ?? ContractionMath.summary(data.contractions)
        guard let interval = summary.avgIntervalSeconds else { return "\(summary.count) 次" }
        return "\(summary.count) 次 · 约 \(seconds(interval))一次"
    }
}
