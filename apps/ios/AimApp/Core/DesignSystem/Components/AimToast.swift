import SwiftUI

struct AimToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    var undoTitle: String = "撤销"
    var accessibilityIdentifier: String = "aim-toast"
    var undo: (() -> Void)?

    static func == (lhs: AimToastMessage, rhs: AimToastMessage) -> Bool { lhs.id == rhs.id }
}

private struct AimToastModifier: ViewModifier {
    @Binding var message: AimToastMessage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                toast(message)
                    .padding(.horizontal, AimMetrics.space16)
                    .padding(.bottom, AimMetrics.space12)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: message.id) {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation { self.message = nil }
                    }
            }
        }
        .animation(.snappy, value: message)
    }

    private func toast(_ message: AimToastMessage) -> some View {
        HStack(spacing: AimMetrics.space12) {
            Image(systemName: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.aimSuccess)
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(Color.aimTextOnAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let undo = message.undo {
                Button(message.undoTitle) {
                    undo()
                    self.message = nil
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.aimAccent)
            }
            Button {
                self.message = nil
            } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .foregroundStyle(Color.aimTextTertiary)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, AimMetrics.space16)
        .padding(.vertical, AimMetrics.space12)
        .background(Color.aimTextPrimary, in: RoundedRectangle(cornerRadius: AimMetrics.radiusToast, style: .continuous))
        .accessibilityIdentifier(message.accessibilityIdentifier)
    }
}

extension View {
    func aimToast(_ message: Binding<AimToastMessage?>) -> some View {
        modifier(AimToastModifier(message: message))
    }
}
