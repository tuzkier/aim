import SwiftUI

/// 首页头部。大标题是孕周而不是日期——时间线的主语是孕期进程。
/// 整块标题可点，是进入完整时间线的主入口；右侧只留「+」和 Agent 两颗钮，
/// 筛选跟着时间线走了。
struct HomeHeader: View {
    let week: Int?
    let days: Int
    let date: Date
    let stageName: String?
    /// 设了就用它作标题（待办标签用「待办」），不再显示孕周——孕周在首页。
    var title: String? = nil
    let onOpenTimeline: () -> Void
    let onNewTask: () -> Void
    let onNewRecord: () -> Void
    let onAgent: () -> Void

    /// 圆钮里的图标随动态字号放大，容器也得跟着长，否则 AX 大字号下两颗钮会叠在一起。
    @ScaledMetric(relativeTo: .subheadline) private var circleSize: CGFloat = AimMetrics.circleButtonSize

    var body: some View {
        HStack(alignment: .bottom) {
            Button(action: onOpenTimeline) {
                VStack(alignment: .leading, spacing: AimMetrics.space4) {
                    Text(captionText)
                        .font(.caption2)
                        .tracking(0.9)
                        .foregroundStyle(Color.aimAccent)
                    HStack(alignment: .firstTextBaseline, spacing: AimMetrics.space4) {
                        Text(titleText)
                            .font(.largeTitle.weight(.medium))
                            .foregroundStyle(Color.aimTextPrimary)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.aimTextTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(titleText)，查看完整时间线")
            .accessibilityIdentifier("home-header-week")

            Spacer(minLength: AimMetrics.space8)

            HStack(spacing: AimMetrics.space8) {
                Menu {
                    Button("新建待办", systemImage: "checkmark.circle", action: onNewTask)
                    Button("新增记录", systemImage: "square.and.pencil", action: onNewRecord)
                } label: {
                    circle("plus", tinted: false)
                }
                .accessibilityLabel("新增")
                .accessibilityIdentifier("home-add-menu")

                Button(action: onAgent) { circle("wand.and.sparkles", tinted: true) }
                    .accessibilityLabel("AIM")
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
            .frame(width: circleSize, height: circleSize)
            .background(tinted ? Color.aimAccentSoft : Color.aimSurface, in: Circle())
            .overlay {
                if !tinted { Circle().stroke(Color.aimSeparator, lineWidth: 1) }
            }
    }

    private var titleText: String {
        if let title { return title }
        guard let week else { return "孕期" }
        return days > 0 ? "孕 \(week) 周 + \(days) 天" : "孕 \(week) 周"
    }

    private var captionText: String {
        let formatter = DateFormatter()
        formatter.calendar = PregnancyDateCalculator.calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        let dateText = formatter.string(from: date)
        guard let stageName, title == nil else { return dateText }
        return dateText + " · " + stageName
    }
}
