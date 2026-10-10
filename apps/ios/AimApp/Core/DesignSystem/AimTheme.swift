import SwiftUI

extension Color {
    static let aimCanvas = Color("AimCanvas")
    static let aimSurface = Color("AimSurface")
    static let aimSurfaceRaised = Color("AimSurfaceRaised")
    static let aimSurfaceSunken = Color("AimSurfaceSunken")
    static let aimSeparator = Color("AimSeparator")
    static let aimRail = Color("AimRail")
    static let aimTextPrimary = Color("AimTextPrimary")
    static let aimTextSecondary = Color("AimTextSecondary")
    static let aimTextTertiary = Color("AimTextTertiary")
    static let aimTextOnAccent = Color("AimTextOnAccent")
    static let aimAccent = Color("AimAccent")
    static let aimAccentSoft = Color("AimAccentSoft")
    static let aimSuccess = Color("AimSuccess")
    static let aimSuccessSoft = Color("AimSuccessSoft")
    static let aimDanger = Color("AimDanger")
    static let aimDangerSoft = Color("AimDangerSoft")
    /// 提醒色（琥珀）：「今天或明天联系医院」这一档，介于强调色与危险色之间。
    static let aimWarning = Color("AimWarning")
    static let aimWarningSoft = Color("AimWarningSoft")
}

struct AimCard: ViewModifier {
    var radius: CGFloat = AimMetrics.radiusCard

    func body(content: Content) -> some View {
        content
            .padding(AimMetrics.space16)
            .background(Color.aimSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.aimSeparator, lineWidth: 1)
            }
    }
}

extension View {
    func aimCard(radius: CGFloat = AimMetrics.radiusCard) -> some View {
        modifier(AimCard(radius: radius))
    }

    func aimLabelStyle() -> some View {
        font(.caption2)
            .tracking(0.9)
            .foregroundStyle(Color.aimTextTertiary)
    }
}
