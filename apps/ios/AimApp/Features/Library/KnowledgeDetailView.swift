import SwiftUI

/// 一条知识条目的详情。按形态渲染——菜谱出食材清单和编号步骤，
/// 「能不能吃」把结论放最上面，而不是把所有形态都摊成一段文字。
struct KnowledgeDetailView: View {
    let entry: KnowledgeEntry

    var body: some View {
        List {
            switch entry.data.form {
            case .recipe:
                section("食材", items: entry.data.ingredients ?? [])
                numberedSection("做法", steps: entry.data.steps ?? [])
            case .foodRule:
                Section {
                    Text(entry.data.verdict?.displayName ?? "待确认")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(verdictColor)
                    if let reason = entry.data.reason { Text(reason) }
                }
                .listRowBackground(Color.aimSurface)
            case .howto:
                numberedSection("步骤", steps: entry.data.steps ?? [])
            case .tip, .unknown:
                Section { Text(entry.data.body ?? "") }
                    .listRowBackground(Color.aimSurface)
            }

            if let note = entry.data.note, !note.isEmpty {
                Section("补充") { Text(note) }
                    .listRowBackground(Color.aimSurface)
            }

            Section {
                Text("由 AIM 依据对话整理，不替代产检医生的意见。")
                    .font(.caption)
                    .foregroundStyle(Color.aimTextTertiary)
            }
            .listRowBackground(Color.aimSurface)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.aimCanvas)
        .navigationTitle(entry.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private var verdictColor: Color {
        switch entry.data.verdict {
        case .avoid: Color.aimDanger
        case .limit: Color.aimAccent
        case .safe: Color.aimSuccess
        default: Color.aimTextSecondary
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [String]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items, id: \.self) { Text($0) }
            }
            .listRowBackground(Color.aimSurface)
        }
    }

    @ViewBuilder
    private func numberedSection(_ title: String, steps: [String]) -> some View {
        if !steps.isEmpty {
            Section(title) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
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
