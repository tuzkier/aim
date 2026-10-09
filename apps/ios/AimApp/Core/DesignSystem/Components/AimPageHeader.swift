import SwiftUI

/// 标签页统一的顶部：灰色小字说明 + 大标题 + 右侧圆形按钮。
///
/// 首页、待办、资料库、家庭四个标签共用，切标签时顶部不再像换了一个 App。
struct AimPageHeader<Trailing: View>: View {
    let caption: String?
    let title: String
    /// 标题可点时（待办页点标题进完整时间线）显示一个小箭头。
    var titleAction: (() -> Void)?
    var titleIdentifier: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: AimMetrics.space8) {
            VStack(alignment: .leading, spacing: 2) {
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Color.aimTextSecondary)
                }
                if let titleAction {
                    Button(action: titleAction) {
                        HStack(alignment: .firstTextBaseline, spacing: AimMetrics.space4) {
                            titleText
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.aimTextTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(titleIdentifier ?? "")
                } else {
                    titleText.accessibilityIdentifier(titleIdentifier ?? "")
                }
            }
            Spacer(minLength: AimMetrics.space8)
            trailing()
        }
        .padding(.top, AimMetrics.space8)
    }

    private var titleText: some View {
        Text(title)
            .font(.title.weight(.semibold))
            .foregroundStyle(Color.aimTextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// 顶部右侧的圆形按钮。`tinted` 用于 AIM 这类主要入口。
struct AimCircleButton: View {
    let symbol: String
    var tinted = false
    let label: String
    var identifier: String?
    let action: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = AimMetrics.circleButtonSize

    var body: some View {
        Button(action: action) { AimCircleIcon(symbol: symbol, tinted: tinted, size: size) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier ?? "")
    }
}

/// 圆形按钮的外观，也给 `Menu` 的标签用。
struct AimCircleIcon: View {
    let symbol: String
    var tinted = false
    var size: CGFloat = AimMetrics.circleButtonSize

    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline)
            .foregroundStyle(tinted ? Color.aimAccent : Color.aimTextSecondary)
            .frame(width: size, height: size)
            .background(tinted ? Color.aimAccentSoft : Color.aimSurface, in: Circle())
            .overlay { if !tinted { Circle().stroke(Color.aimSeparator) } }
    }
}

extension View {
    /// 卡片里的标题，以及待办长列表的分组标题。与首页「这一周」「今天」一致。
    func aimSectionTitle() -> some View {
        font(.headline).foregroundStyle(Color.aimTextPrimary)
    }
}
