import SwiftUI

struct AimFocusCard: View {
    let task: TaskItem
    var actionTitle: String = "开始处理"
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Text("现在最重要").aimLabelStyle()
            Text(task.title)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.aimTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = task.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.aimTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onAction) {
                Text(actionTitle)
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AimMetrics.space12)
                    .background(Color.aimAccent, in: RoundedRectangle(cornerRadius: AimMetrics.radiusButton, style: .continuous))
                    .foregroundStyle(Color.aimTextOnAccent)
            }
            .buttonStyle(.plain)
            .padding(.top, AimMetrics.space4)
        }
        .aimCard()
        .accessibilityIdentifier("timeline-focus-card")
    }
}
