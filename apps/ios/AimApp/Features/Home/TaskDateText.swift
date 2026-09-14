import Foundation

/// 任务行元信息里的相对日期。首页和时间线共用，保证同一个截止时间在两处显示一致。
///
/// 快速添加的待办没有让用户选时刻，截止时间统一落在当天 23:59；这个时刻是哨兵值，
/// 显示时把它藏掉——用户看到「今天」就够了，「今天 23:59」反而像个真实的 deadline。
enum TaskDateText {
    static func endOfDay(_ date: Date, calendar: Calendar = PregnancyDateCalculator.calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: start) ?? start
    }

    static func isEndOfDaySentinel(_ date: Date, calendar: Calendar = PregnancyDateCalculator.calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return parts.hour == 23 && parts.minute == 59
    }

    static func label(for date: Date, now: Date, calendar: Calendar = PregnancyDateCalculator.calendar) -> String {
        let dayDiff = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0

        let day: String
        switch dayDiff {
        case 0: day = "今天"
        case 1: day = "明天"
        case -1: day = "昨天"
        case 2...6: day = format(date, "EEE", calendar: calendar)
        case -7 ... -2: day = "\(-dayDiff) 天前"
        default: day = format(date, "M月d日", calendar: calendar)
        }

        guard !isEndOfDaySentinel(date, calendar: calendar) else { return day }
        return day + " " + format(date, "HH:mm", calendar: calendar)
    }

    private static func format(_ date: Date, _ pattern: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
