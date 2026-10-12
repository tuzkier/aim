import Foundation

/// 「我们出发去医院了」：一条全家可见的记录。没有推送，家人打开 App 时在首页看到横幅。
enum HospitalTrip {
    static let title = "我们出发去医院了"
    static let bannerWindow: TimeInterval = 86_400

    static func draft(reason: HospitalTripReason, note: String, contractionRecordID: UUID?, at now: Date) -> RecordDraft {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return RecordDraft(
            type: .hospitalTrip, occurredAt: now, visibility: .family, title: title,
            content: trimmed.isEmpty ? nil : String(trimmed.prefix(200)),
            structuredData: .hospitalTrip(HospitalTripRecordData(reason: reason, contractionRecordID: contractionRecordID)))
    }

    /// 首页要显示的那一条：24 小时内最新的一条；别人发的、本机已点「知道了」的不算。
    static func banner(in records: [RecordItem], now: Date, me: UUID?, dismissed: Set<UUID>) -> RecordItem? {
        records
            .filter { record in
                guard record.type == .hospitalTrip else { return false }
                let age = now.timeIntervalSince(record.occurredAt)
                guard age >= -300, age <= bannerWindow else { return false }
                return record.authorAccountID == me || !dismissed.contains(record.id)
            }
            .max { $0.occurredAt < $1.occurredAt }
    }

    /// 「妈妈 10:32 出发去医院了 · 规律宫缩」
    static func bannerText(_ record: RecordItem, actorName: String) -> String {
        let time = record.occurredAt.formatted(date: .omitted, time: .shortened)
        let detail: String = {
            if let note = record.content?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { return note }
            if case let .hospitalTrip(data) = record.structuredData { return data.reason.displayName }
            return ""
        }()
        let base = "\(actorName) \(time) 出发去医院了"
        return detail.isEmpty ? base : "\(base) · \(detail)"
    }
}

/// 本机已点「知道了」的去医院记录。
struct HospitalTripDismissals {
    private static let key = "aim.hospitalTrip.dismissed"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var ids: Set<UUID> {
        Set((defaults.stringArray(forKey: Self.key) ?? []).compactMap(UUID.init(uuidString:)))
    }

    func dismiss(_ id: UUID) {
        defaults.set((ids.union([id])).map(\.uuidString), forKey: Self.key)
    }
}
