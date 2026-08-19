import SwiftUI

struct AgentDiffSheet: View {
    let preview: AgentChangePreview
    let onApply: () -> Void
    let onDismiss: () -> Void

    @State private var applied = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AimMetrics.space20) {
                VStack(alignment: .leading, spacing: AimMetrics.space4) {
                    Text("确认计划变更")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.aimTextPrimary)
                    Text("先确认 Aim 理解得对，再决定是否写入家庭计划。")
                        .font(.subheadline)
                        .foregroundStyle(Color.aimTextSecondary)
                }

                VStack(alignment: .leading, spacing: AimMetrics.space4) {
                    Text("我理解的是").aimLabelStyle()
                    Text(preview.understanding)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.aimTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let qualifier = preview.qualifier {
                        Text(qualifier)
                            .font(.subheadline)
                            .foregroundStyle(Color.aimTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !preview.changes.isEmpty {
                    VStack(alignment: .leading, spacing: AimMetrics.space8) {
                        Text("计划将这样变化").aimLabelStyle()
                        VStack(spacing: 0) {
                            ForEach(Array(preview.changes.enumerated()), id: \.element.id) { index, row in
                                changeRow(row)
                                if index < preview.changes.count - 1 {
                                    Divider().background(Color.aimSeparator)
                                }
                            }
                        }
                        .padding(.horizontal, AimMetrics.space12)
                        .background(Color.aimSurfaceSunken,
                                    in: RoundedRectangle(cornerRadius: AimMetrics.radiusDiffCard, style: .continuous))
                    }
                }

                HStack(alignment: .top, spacing: AimMetrics.space8) {
                    Image(systemName: "checkmark.shield")
                        .font(.footnote)
                        .foregroundStyle(Color.aimSuccess)
                    Text(AgentChangePreview.safetyNote)
                        .font(.footnote)
                        .foregroundStyle(Color.aimSuccess)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AimMetrics.space12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.aimSuccessSoft,
                            in: RoundedRectangle(cornerRadius: AimMetrics.radiusButton, style: .continuous))

                VStack(spacing: AimMetrics.space4) {
                    Button {
                        applied += 1
                        onApply()
                    } label: {
                        Text(preview.applyTitle)
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AimMetrics.space12)
                            .background(Color.aimAccent,
                                        in: RoundedRectangle(cornerRadius: AimMetrics.radiusButton, style: .continuous))
                            .foregroundStyle(Color.aimTextOnAccent)
                    }
                    .buttonStyle(.plain)

                    Button("暂不修改", action: onDismiss)
                        .font(.body)
                        .foregroundStyle(Color.aimTextSecondary)
                        .padding(.vertical, AimMetrics.space8)
                }
            }
            .padding(AimMetrics.space20)
        }
        .background(Color.aimSurfaceRaised)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("agent-diff-sheet")
        .sensoryFeedback(.success, trigger: applied)
    }

    private func changeRow(_ row: AgentChangeRow) -> some View {
        HStack(alignment: .top, spacing: AimMetrics.space12) {
            Image(systemName: row.symbol)
                .font(.subheadline)
                .foregroundStyle(Color.aimAccent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.field)
                    .font(.subheadline)
                    .foregroundStyle(Color.aimTextPrimary)
                Text(row.valueText)
                    .font(.footnote)
                    .foregroundStyle(Color.aimTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AimMetrics.space12)
        .accessibilityElement(children: .combine)
    }
}
