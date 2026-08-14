import SwiftUI

extension Color {
    static let aimAccent = Color("AccentColor")
    static let aimWarmBackground = Color(red: 0.985, green: 0.972, blue: 0.957)
    static let aimWarmSurface = Color(red: 1.0, green: 0.992, blue: 0.982)
    static let aimSoftRose = Color(red: 0.98, green: 0.90, blue: 0.88)
    static let aimSoftSand = Color(red: 0.96, green: 0.92, blue: 0.84)
}

struct AimWarmCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color.aimWarmSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
            }
    }
}

extension View {
    func aimWarmCard() -> some View { modifier(AimWarmCard()) }
}
