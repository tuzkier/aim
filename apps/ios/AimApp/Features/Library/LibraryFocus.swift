import Foundation

/// 资料库顶部「本周关注」。
///
/// 它回答「我现在最该看什么」，而不是让用户自己在六个分类里找。
/// 没有值得关注的事就不显示——空的横幅比没有横幅更糟。
///
/// 措辞守一条红线：只说该去找谁、多急，不下任何诊断性判断。
/// 规则命中的是数据模式，不是医学结论。
struct LibraryFocus: Equatable, Sendable {
    /// 有多急。决定横幅的颜色、位置，以及要不要直接给出拨号按钮。
    enum Level: Equatable, Sendable {
        /// 立即就医。
        case urgent
        /// 今天联系产检医院。
        case soon
        /// 记下来、下次产检带上。
        case info
    }

    let headline: String
    var tags: [String] = []
    var level: Level = .info

    /// 「偏高」的门槛：高压 ≥140 或低压 ≥90。用两次而不是一次——单次偏高很常见
    /// （紧张、刚走完路），一次就报会让用户很快学会忽略这个位置。
    private static let highSystolic: Double = 140
    private static let highDiastolic: Double = 90
    private static let consecutiveHighReadingsNeeded = 2
    /// 「很高」的门槛：高压 ≥160 或低压 ≥110。和危险信号的升档线一致，一次就够。
    private static let severeSystolic: Double = 160
    private static let severeDiastolic: Double = 110
    /// 时效：很高档只认 7 天内的读数（8–14 天前的降为「今天联系复测」），
    /// 连续偏高档要求最近一次在 14 天内。几周前量的血压已经说明不了「现在」，
    /// 拿它喊立即就医只会让人不再信这个位置。
    private static let severeFreshnessDays = 7
    private static let highFreshnessDays = 14
    private static let repeatedSymptomThreshold = 3

    static func make(from snapshot: LibrarySnapshot, now: Date = .now) -> LibraryFocus? {
        // 顺序即优先级：身体信号 > 反复症状 > 攒下的事务。
        bloodPressure(from: snapshot, now: now)
            ?? repeatedSymptom(from: snapshot, now: now)
            ?? pendingQuestions(from: snapshot)
    }

    private static func bloodPressure(from snapshot: LibrarySnapshot, now: Date) -> LibraryFocus? {
        // 高压、低压都要看：140/90 和 160/110 都是「或」的关系，
        // 只看收缩压会漏掉单纯舒张压高的情况。没测血压的产检不算一次读数。
        let readings = snapshot.records
            .compactMap { record -> (date: Date, metrics: CheckupMetrics)? in
                guard record.type == .checkup,
                      case let .checkup(data) = record.structuredData,
                      data.metrics.systolic != nil || data.metrics.diastolic != nil else { return nil }
                return (record.occurredAt, data.metrics)
            }
            .sorted { $0.date < $1.date }
        guard let latest = readings.last else { return nil }

        let latestIsSevere = (latest.metrics.systolic ?? 0) >= severeSystolic
            || (latest.metrics.diastolic ?? 0) >= severeDiastolic
        // 最近一次就到了升档线，不能再等第二次——和危险信号一样要立即就医。
        if latestIsSevere, isWithin(days: severeFreshnessDays, of: latest.date, now: now) {
            return LibraryFocus(
                headline: "血压很高，请立即联系产检医院或去急诊",
                tags: ["指标 1 条"],
                level: .urgent
            )
        }
        // 一周多以前很高、之后没再量：说不清现在怎样，但不能比「两次偏高」提示得还弱。
        // 它单独成立，也优先于「连续偏高」——要做的事更具体：复测。
        if latestIsSevere, isWithin(days: highFreshnessDays, of: latest.date, now: now) {
            return LibraryFocus(
                headline: "上次血压很高，今天联系产检医院复测",
                tags: ["指标 1 条"],
                level: .soon
            )
        }

        let recent = readings.suffix(consecutiveHighReadingsNeeded)
        guard isWithin(days: highFreshnessDays, of: latest.date, now: now),
              recent.count == consecutiveHighReadingsNeeded,
              recent.allSatisfy({
                  ($0.metrics.systolic ?? 0) >= highSystolic
                      || ($0.metrics.diastolic ?? 0) >= highDiastolic
              }) else { return nil }

        return LibraryFocus(
            headline: "血压连续偏高，今天联系你的产检医院",
            tags: ["指标 \(recent.count) 条"],
            level: .soon
        )
    }

    private static func isWithin(days: Int, of date: Date, now: Date) -> Bool {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else {
            return false
        }
        return date >= cutoff
    }

    private static func repeatedSymptom(from snapshot: LibrarySnapshot, now: Date) -> LibraryFocus? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        var counts: [String: Int] = [:]
        for record in snapshot.records where record.type == .symptom && record.occurredAt >= cutoff {
            guard case let .symptom(data) = record.structuredData else { continue }
            for label in data.symptoms { counts[label, default: 0] += 1 }
        }
        guard let worst = counts.filter({ $0.value >= repeatedSymptomThreshold })
            .max(by: { $0.value < $1.value }) else { return nil }

        return LibraryFocus(
            headline: "这周记录了 \(worst.value) 次「\(worst.key)」，可以问问医生",
            tags: ["身体感受 \(worst.value) 条"]
        )
    }

    private static func pendingQuestions(from snapshot: LibrarySnapshot) -> LibraryFocus? {
        let pending = snapshot.records.filter { record in
            guard record.type == .question,
                  case let .question(data) = record.structuredData else { return false }
            return !data.answered
        }
        guard !pending.isEmpty else { return nil }

        return LibraryFocus(
            headline: "攒了 \(pending.count) 个问题，下次产检一次带走",
            tags: ["待问医生 \(pending.count) 个"]
        )
    }
}
