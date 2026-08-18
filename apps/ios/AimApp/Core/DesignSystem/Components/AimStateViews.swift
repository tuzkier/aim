import SwiftUI

struct AimEmptyState: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Text(title).font(.title3.weight(.medium))
        } description: {
            Text(message).foregroundStyle(Color.aimTextSecondary)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.aimAccent)
            }
        }
    }
}

struct AimErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("暂时加载不出来", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message).foregroundStyle(Color.aimTextSecondary)
        } actions: {
            Button("重试", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(Color.aimAccent)
        }
        .accessibilityIdentifier("error-state")
    }
}
