import SwiftUI

/// 写入知识条目前的确认卡。
///
/// 按形态渲染要写入的内容——菜谱出食材和编号步骤，「能不能吃」把结论放最上面。
/// 用户否决的原因通常不是"不该存"，而是"内容不对"，所以必须看得见内容本身。
struct KnowledgeApprovalSheet: View {
    let preview: KnowledgePreview
    let onApprove: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: AimMetrics.space4) {
                        Text("将收录到「\(preview.categoryTitle)」· \(preview.formTitle)")
                            .font(.caption)
                            .foregroundStyle(Color.aimTextTertiary)
                        Text(preview.title)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Color.aimTextPrimary)
                    }
                }
                .listRowBackground(Color.aimSurface)

                switch preview.data.form {
                case .recipe:
                    items("食材", preview.data.ingredients ?? [])
                    steps(preview.data.steps ?? [])
                case .foodRule:
                    Section {
                        Text(preview.data.verdict?.displayName ?? "待确认")
                            .font(.headline)
                            .foregroundStyle(verdictColor)
                        if let reason = preview.data.reason { Text(reason) }
                    }
                    .listRowBackground(Color.aimSurface)
                case .howto:
                    steps(preview.data.steps ?? [])
                case .tip, .unknown:
                    Section { Text(preview.data.body ?? "") }
                        .listRowBackground(Color.aimSurface)
                }

                Section {
                    // 固定文案，不接受模型生成的内容——它是产品承诺。
                    Text("AIM 依据对话整理，可能有误。收录后可以随时删除。")
                        .font(.caption)
                        .foregroundStyle(Color.aimTextSecondary)
                }
                .listRowBackground(Color.aimSuccessSoft)

                Section {
                    Button(action: onApprove) {
                        Text("收录").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("knowledge-approve")
                    Button("先不收录", action: onDismiss)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.aimSurface)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.aimCanvas)
            .navigationTitle("确认收录")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("knowledge-approval-sheet")
    }

    private var verdictColor: Color {
        switch preview.data.verdict {
        case .avoid: Color.aimDanger
        case .limit: Color.aimAccent
        case .safe: Color.aimSuccess
        default: Color.aimTextSecondary
        }
    }

    @ViewBuilder
    private func items(_ title: String, _ values: [String]) -> some View {
        if !values.isEmpty {
            Section(title) { ForEach(values, id: \.self) { Text($0) } }
                .listRowBackground(Color.aimSurface)
        }
    }

    @ViewBuilder
    private func steps(_ values: [String]) -> some View {
        if !values.isEmpty {
            Section("做法") {
                ForEach(Array(values.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: AimMetrics.space8) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.medium))
                            .frame(width: 20, height: 20)
                            .background(Color.aimAccentSoft, in: Circle())
                            .foregroundStyle(Color.aimAccent)
                        Text(step)
                    }
                }
            }
            .listRowBackground(Color.aimSurface)
        }
    }
}
