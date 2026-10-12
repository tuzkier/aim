import Foundation

/// 「我们出发去医院了」：一条全家可见的记录。没有推送，家人打开 App 时在首页看到横幅。
enum HospitalTrip {
    static let title = "我们出发去医院了"
    static let bannerWindow: TimeInterval = 86_400

    static func draft(reason: HospitalTripReason, note: String, contractionRecordID: UUID?, at now: Date) -> RecordDraft {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return RecordDraft(
            type: .hospitalTrip, occurredAt: now, visibility: .family, title: title,
            // 服务端按 Unicode 码点数校验 ≤ 200，这里也按码点截断，而不是按字素簇。
            content: trimmed.isEmpty ? nil : String(String.UnicodeScalarView(trimmed.unicodeScalars.prefix(200))),
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

    /// 「妈妈 10:32 出发去医院了 · 规律宫缩」，有备注时为「… · 规律宫缩 · 爸爸陪着」
    static func bannerText(_ record: RecordItem, actorName: String) -> String {
        let time = record.occurredAt.formatted(date: .omitted, time: .shortened)
        var parts = ["\(actorName) \(time) 出发去医院了"]
        // 原因始终要显示：家人必须看到「破水」「出血」这类信息；有备注时接在原因后面。
        if case let .hospitalTrip(data) = record.structuredData { parts.append(data.reason.displayName) }
        if let note = record.content?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

/// 打开「我们出发去医院了」确认页的一次请求，带上要关联的宫缩记录。
struct HospitalTripLaunch: Identifiable {
    let id = UUID()
    let contractionRecordID: UUID?
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
