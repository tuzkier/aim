import SwiftUI

struct TimelineHeader: View {
    let week: Int?
    let days: Int
    let date: Date
    @Binding var filter: TimelineFilter
    let onCompose: () -> Void
    let onAgent: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: AimMetrics.space4) {
                Text(dateText)
                    .font(.caption2)
                    .tracking(0.9)
                    .foregroundStyle(Color.aimAccent)
                Text(titleText)
                    .font(.largeTitle.weight(.medium))
                    .foregroundStyle(Color.aimTextPrimary)
            }
            Spacer(minLength: AimMetrics.space8)
            HStack(spacing: AimMetrics.space8) {
                Menu {
                    Picker("筛选", selection: $filter) {
                        ForEach(TimelineFilter.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                } label: {
                    circle("line.3.horizontal.decrease", tinted: filter != .all)
                }
                .accessibilityLabel("筛选")
                .accessibilityIdentifier("timeline-filter")

                Button(action: onCompose) { circle("plus", tinted: false) }
                    .accessibilityLabel("新增记录")

                Button(action: onAgent) { circle("wand.and.sparkles", tinted: true) }
                    .accessibilityLabel("问一问")
                    .accessibilityIdentifier("global-agent-button")
            }
        }
        .padding(.horizontal, AimMetrics.space20)
        .padding(.bottom, AimMetrics.space12)
    }

    private func circle(_ symbol: String, tinted: Bool) -> some View {
        Image(systemName: symbol)
            .font(.subheadline)
            .foregroundStyle(tinted ? Color.aimAccent : Color.aimTextSecondary)
            .frame(width: AimMetrics.circleButtonSize, height: AimMetrics.circleButtonSize)
            .background(tinted ? Color.aimAccentSoft : Color.aimSurface, in: Circle())
            .overlay {
                if !tinted { Circle().stroke(Color.aimSeparator, lineWidth: 1) }
            }
    }

    private var titleText: String {
        guard let week else { return "孕期" }
        return days > 0 ? "孕 \(week) 周 + \(days) 天" : "孕 \(week) 周"
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.calendar = PregnancyDateCalculator.calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }
}
