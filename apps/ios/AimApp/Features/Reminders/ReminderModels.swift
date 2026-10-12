import Foundation

struct ReminderScope: Codable, Equatable, Sendable {
    let accountID: UUID
    let familyID: UUID
    let pregnancyID: UUID
    var key: String { [accountID, familyID, pregnancyID].map { $0.uuidString.lowercased() }.joined(separator: ".") }

    @MainActor
    init?(session: AppSessionStore) {
        guard session.isConfigured, let account = session.accountID,
              let family = session.familyID, let pregnancy = session.pregnancyID else { return nil }
        self.init(accountID: account, familyID: family, pregnancyID: pregnancy)
    }

    init(accountID: UUID, familyID: UUID, pregnancyID: UUID) {
        self.accountID = accountID; self.familyID = familyID; self.pregnancyID = pregnancyID
    }
}

struct ReminderPreferences: Codable, Equatable, Sendable {
    var enabled = false
    var fetalMovement = true
    var fetalMinute = 20 * 60
    var tasks = true
    var weekly = true
    var quiet = true
    var quietStart = 22 * 60
    var quietEnd = 8 * 60

    var isValid: Bool {
        [fetalMinute, quietStart, quietEnd].allSatisfy { (0..<1440).contains($0) }
            && (!enabled || !quiet || quietStart != quietEnd)
    }

    func isQuiet(_ date: Date) -> Bool {
        guard quiet else { return false }
        let parts = ReminderPlanner.calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return quietStart < quietEnd
            ? (quietStart..<quietEnd).contains(minute)
            : minute >= quietStart || minute < quietEnd
    }
}

enum ReminderKind: String, Codable, Sendable {
    case task, fetalMovement, weekly
    var title: String {
        switch self {
        case .task: "产检与待办"
        case .fetalMovement: "胎动提醒"
        case .weekly: "本周简报"
        }
    }
    var body: String {
        switch self {
        case .task: "有一项安排即将到期，打开 Aim 查看最新详情。"
        case .fetalMovement: "如果今天还没记录胎动，可以打开计数页。"
        case .weekly: "打开 Aim，看看本周的待办与最近记录。"
        }
    }
}

struct ReminderRoute: Equatable, Sendable {
    let scope: ReminderScope
    let kind: ReminderKind
    var taskID: UUID?

    var userInfo: [String: String] {
        var info = ["account_id": scope.accountID.uuidString, "family_id": scope.familyID.uuidString,
                    "pregnancy_id": scope.pregnancyID.uuidString, "kind": kind.rawValue]
        if let taskID { info["task_id"] = taskID.uuidString }
        return info
    }

    init(scope: ReminderScope, kind: ReminderKind, taskID: UUID? = nil) {
        self.scope = scope; self.kind = kind; self.taskID = taskID
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let a = userInfo["account_id"] as? String, let account = UUID(uuidString: a),
              let f = userInfo["family_id"] as? String, let family = UUID(uuidString: f),
              let p = userInfo["pregnancy_id"] as? String, let pregnancy = UUID(uuidString: p),
              let k = userInfo["kind"] as? String, let kind = ReminderKind(rawValue: k) else { return nil }
        let task = (userInfo["task_id"] as? String).flatMap(UUID.init(uuidString:))
        guard kind != .task || task != nil else { return nil }
        self.init(scope: ReminderScope(accountID: account, familyID: family, pregnancyID: pregnancy),
                  kind: kind, taskID: task)
    }
}

struct PlannedReminder: Equatable, Sendable, Identifiable {
    let id: String
    let fireAt: Date
    let route: ReminderRoute
    var isTest = false
}

enum ReminderPlanner {
    static let prefix = "aim.reminder."
    static let horizonDays = 28
    static let budget = 60
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    static func make(scope: ReminderScope, preferences: ReminderPreferences, pregnancy: PregnancySummary,
                     tasks: [TaskItem], records: [RecordItem], activeCount: Date? = nil,
                     now: Date) -> [PlannedReminder] {
        guard preferences.enabled, preferences.isValid, pregnancy.id == scope.pregnancyID else { return [] }
        let cal = calendar
        let end = cal.date(byAdding: .day, value: horizonDays, to: now)!
        var candidates: [PlannedReminder] = []
        if preferences.tasks {
            for task in tasks where task.isOpen && task.status != .unknown
                && (task.assignedMemberID == nil || task.assignedMemberID == scope.accountID) {
                // 与待办列表一致：改期会更新 dueAt，scheduledFor 可能仍是原来的时间。
                guard let due = task.dueAt ?? task.scheduledFor else { continue }
                let early = due.addingTimeInterval(-3600)
                // 新建或改期到不足一小时后的事项，改在到期时提醒；过期事项仍不补发。
                let fire = avoidingQuiet(early > now ? early : due, preferences, beforeDeadline: true)
                guard fire > now, fire <= end else { continue }
                candidates.append(PlannedReminder(id: prefix + scope.key + ".task." + task.id.uuidString,
                    fireAt: fire, route: ReminderRoute(scope: scope, kind: .task, taskID: task.id)))
            }
        }
        let start = cal.date(byAdding: .day, value: -280, to: cal.startOfDay(for: pregnancy.dueDate))!
        for offset in 0..<horizonDays {
            let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
            if preferences.fetalMovement && !pregnancy.isPostpartum {
                let time = atMinute(preferences.fetalMinute, on: day)
                let fire = avoidingQuiet(time, preferences, beforeDeadline: false)
                let elapsed = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: fire)).day ?? -1
                let week = elapsed / 7
                let alreadyCounted = records.contains {
                    $0.type == .fetalMovement && $0.pregnancyID == scope.pregnancyID
                        && $0.familyID == scope.familyID && cal.isDate($0.occurredAt, inSameDayAs: fire)
                } || activeCount.map { cal.isDate($0, inSameDayAs: fire) } == true
                if (28...42).contains(week), fire > now, fire <= end, !alreadyCounted {
                    candidates.append(PlannedReminder(id: prefix + scope.key + ".fetal." + dayKey(fire),
                        fireAt: fire, route: ReminderRoute(scope: scope, kind: .fetalMovement)))
                }
            }
            if preferences.weekly, cal.component(.weekday, from: day) == 2 {
                let fire = avoidingQuiet(atMinute(9 * 60, on: day), preferences, beforeDeadline: false)
                if fire > now, fire <= end {
                    candidates.append(PlannedReminder(id: prefix + scope.key + ".weekly." + dayKey(fire),
                        fireAt: fire, route: ReminderRoute(scope: scope, kind: .weekly)))
                }
            }
        }
        // 同一条待办或日期只保留一次，按最近时间取本机预算。
        var seen = Set<String>()
        return Array(candidates.sorted {
            $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt
        }.filter { seen.insert($0.id).inserted }.prefix(budget))
    }

    static func avoidingQuiet(_ date: Date, _ prefs: ReminderPreferences, beforeDeadline: Bool) -> Date {
        guard prefs.isQuiet(date) else { return date }
        let cal = calendar
        if beforeDeadline {
            var start = atMinute(prefs.quietStart, on: date)
            if start > date { start = cal.date(byAdding: .day, value: -1, to: start)! }
            return start.addingTimeInterval(-60)
        }
        var end = atMinute(prefs.quietEnd, on: date)
        if end <= date { end = cal.date(byAdding: .day, value: 1, to: end)! }
        return end
    }

    static func atMinute(_ minute: Int, on day: Date) -> Date {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)!
    }

    private static func dayKey(_ date: Date) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(d.year!)-\(d.month!)-\(d.day!)"
    }
}
