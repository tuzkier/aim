import Foundation

/// 身体感受的频次统计。
///
/// 流水账看不出规律。真正有用的是「什么反复出现、最近还在不在发生、
/// 最难受到什么程度」——那才是产检时值得跟医生说的。
struct SymptomPattern: Identifiable, Equatable, Sendable {
    var id: String { label }
    let label: String
    let count: Int
    /// 距最近一次多少天。总次数相同时，正在发生的比早就停了的更值得看。
    let daysSinceLast: Int
    /// 记录过的最高严重度——最难受的那次才是要跟医生说的。
    let worstSeverity: Int

    static func make(from records: [RecordItem]) -> [SymptomPattern] {
        var counts: [String: Int] = [:]
        var latest: [String: Date] = [:]
        var worst: [String: Int] = [:]

        for record in records where record.type == .symptom {
            guard case let .symptom(data) = record.structuredData else { continue }
            for label in data.symptoms {
                counts[label, default: 0] += 1
                if let existing = latest[label] {
                    latest[label] = max(existing, record.occurredAt)
                } else {
                    latest[label] = record.occurredAt
                }
                worst[label] = max(worst[label] ?? 0, data.severity)
            }
        }

        let calendar = Calendar.current
        return counts.map { label, count in
            let last = latest[label] ?? .now
            let days = calendar.dateComponents([.day], from: last, to: .now).day ?? 0
            return SymptomPattern(
                label: label, count: count,
                daysSinceLast: max(days, 0), worstSeverity: worst[label] ?? 0)
        }
        // 出现多的排前面；同样多时，最近还在发生的排前面。
        .sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.daysSinceLast < $1.daysSinceLast
        }
    }
}
