import SwiftUI

struct AimWeekHeader: View {
    let week: Int
    let startDate: Date
    let endDate: Date
    let position: TimelineWeek.Position
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption2)
                .tracking(0.9)
                .foregroundStyle(position == .current ? Color.aimAccent : Color.aimTextTertiary)
            Spacer(minLength: AimMetrics.space8)
            if count > 0 {
                Text("\(count) 项")
                    .font(.caption2)
                    .foregroundStyle(Color.aimTextTertiary)
            }
        }
        .padding(.vertical, AimMetrics.space8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timeline-week-header-\(week)")
    }

    private var title: String {
        if position == .current { return "今天" }
        return "孕 \(week) 周 · \(range)"
    }

    private var range: String {
        let formatter = DateFormatter()
        formatter.calendar = PregnancyDateCalculator.calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: startDate) + "–" + formatter.string(from: endDate)
    }
}
