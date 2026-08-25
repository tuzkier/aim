import SwiftUI

/// 问诊清单。产检那天举起手机就能给医生看，所以字号刻意放大、
/// 一屏尽量装得下，不放任何装饰。
struct ConsultationListView: View {
    let list: ConsultationList
    let store: LibraryStore

    @Environment(\.dismiss) private var dismiss
    @State private var isMarking = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AimMetrics.space16) {
                    Text("想问医生的 \(list.questions.count) 个问题")
                        .font(.headline)
                        .foregroundStyle(Color.aimTextSecondary)

                    ForEach(Array(list.questions.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: AimMetrics.space12) {
                            Text("\(index + 1)")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Color.aimAccent)
                                .frame(minWidth: 24, alignment: .trailing)
                            Text(item.text)
                                // 给医生看的时候要一眼能读，所以比正文大一档。
                                .font(.title3)
                                .foregroundStyle(Color.aimTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AimMetrics.space20)
            }
            .background(Color.aimCanvas)
            .navigationTitle("问诊清单")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AimMetrics.space8) {
                    Button {
#if os(iOS)
                        UIPasteboard.general.string = list.plainText
#endif
                        copied = true
                    } label: {
                        Label(copied ? "已复制" : "复制清单", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("consultation-copy")

                    // 问诊结束后一次性标记，而不是回去逐条点——那正是此前缺的一步。
                    Button {
                        Task {
                            isMarking = true
                            await store.markQuestionsAnswered(ids: list.recordIDs)
                            isMarking = false
                            dismiss()
                        }
                    } label: {
                        Text(isMarking ? "正在标记…" : "都问过了")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isMarking)
                    .accessibilityIdentifier("consultation-mark-all")
                }
                .padding(AimMetrics.space16)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("consultation-list")
    }
}
