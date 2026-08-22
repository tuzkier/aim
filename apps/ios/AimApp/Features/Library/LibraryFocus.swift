import Foundation

/// 资料库顶部「本周关注」。
///
/// 它回答「我现在最该看什么」，而不是让用户自己在六个分类里找。
/// 没有值得关注的事就不显示——空的横幅比没有横幅更糟。
///
/// 措辞守一条红线：只说「记下来、问医生」，不下任何诊断性判断。
/// 规则命中的是数据模式，不是医学结论。
struct LibraryFocus: Equatable, Sendable {
    let headline: String
    var tags: [String] = []

    /// 收缩压提示的门槛。用两次而不是一次——单次偏高很常见
    /// （紧张、刚走完路），一次就报会让用户很快学会忽略这个位置。
    private static let systolicThreshold: Double = 140
    private static let consecutiveHighReadingsNeeded = 2
    private static let repeatedSymptomThreshold = 3

    static func make(from snapshot: LibrarySnapshot) -> LibraryFocus? {
        // 顺序即优先级：身体信号 > 反复症状 > 攒下的事务。
        bloodPressure(from: snapshot)
            ?? repeatedSymptom(from: snapshot)
            ?? pendingQuestions(from: snapshot)
    }

    private static func bloodPressure(from snapshot: LibrarySnapshot) -> LibraryFocus? {
        guard let trend = MetricTrend.bloodPressure(
            from: snapshot.records.filter { $0.type == .checkup }
        ) else { return nil }

        let recentHigh = trend.points.suffix(consecutiveHighReadingsNeeded)
        guard recentHigh.count == consecutiveHighReadingsNeeded,
              recentHigh.allSatisfy({ $0.value >= systolicThreshold }) else { return nil }

        return LibraryFocus(
            headline: "血压连续两次偏高，下次产检记得带上记录问医生",
            tags: ["指标 \(recentHigh.count) 条", "待问医生"]
        )
    }

    private static func repeatedSymptom(from snapshot: LibrarySnapshot) -> LibraryFocus? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
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
