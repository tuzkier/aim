import SwiftUI

/// 改预产期时的三种填法。
enum DueDateInputMode: String, CaseIterable, Hashable {
    case dueDate
    case lastMenstrualPeriod
    case currentWeek

    var title: String {
        switch self {
        case .dueDate: "预产期"
        case .lastMenstrualPeriod: "末次月经"
        case .currentWeek: "当前孕周"
        }
    }
}

/// 改预产期面板的草稿：三种填法一律按 280 天换算成预产期。
///
/// 与建档页的 `PregnancySetupModel` 分开：建档要求「必须主动选过日期」，
/// 而这里一打开就有当前预产期作为起点。
struct DueDateDraft: Equatable {
    /// 能保存的最大孕周：42 周 0 天，与服务端一致。
    static let maxGestationDays = 42 * 7

    var mode: DueDateInputMode = .dueDate
    /// 预产期或末次月经模式下选的日期。
    var date: Date
    var weeks = 0
    var days = 0
    let today: Date

    private static var calendar: Calendar { PregnancyDateCalculator.calendar }

    init(currentDueDate: Date?, today: Date = .now) {
        let start = Self.calendar.startOfDay(for: today)
        self.today = start
        // 还没有孕期时停在「今天 + 280 天」——那是 0 周，用户一眼就知道要改。
        self.date = Self.calendar.startOfDay(
            for: currentDueDate ?? PregnancyDateCalculator.dueDate(fromLastMenstrualPeriod: start))
    }

    var dueDate: Date {
        switch mode {
        case .dueDate:
            return date
        case .lastMenstrualPeriod:
            return PregnancyDateCalculator.dueDate(fromLastMenstrualPeriod: date)
        case .currentWeek:
            let elapsed = weeks * 7 + days
            return Self.calendar.date(
                byAdding: .day, value: PregnancyDateCalculator.standardGestationDays - elapsed, to: today)!
        }
    }

    /// 今天距末次月经的天数；可能为负（还没到孕期）。
    private var elapsedDays: Int {
        let lastPeriod = PregnancyDateCalculator.lastMenstrualPeriod(fromDueDate: dueDate)
        return Self.calendar.dateComponents([.day], from: lastPeriod, to: today).day ?? 0
    }

    /// 换算出的今天的孕周；超出范围时为 nil。
    var gestation: (weeks: Int, days: Int)? {
        guard validationMessage == nil else { return nil }
        return (elapsedDays / 7, elapsedDays % 7)
    }

    var validationMessage: String? {
        if elapsedDays < 0 { return "这个日期算出来还没到孕期，请检查一下" }
        if elapsedDays > Self.maxGestationDays { return "这个日期算出来已经超过 42 周了，请检查一下" }
        return nil
    }

    /// 换模式时保持同一个预产期，只是换一种说法。
    mutating func switchMode(to newMode: DueDateInputMode) {
        let current = dueDate
        let elapsed = max(0, min(elapsedDays, Self.maxGestationDays))
        mode = newMode
        switch newMode {
        case .dueDate:
            date = current
        case .lastMenstrualPeriod:
            date = PregnancyDateCalculator.lastMenstrualPeriod(fromDueDate: current)
        case .currentWeek:
            weeks = elapsed / 7
            days = elapsed % 7
        }
    }
}
