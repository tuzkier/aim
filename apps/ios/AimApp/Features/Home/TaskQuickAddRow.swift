import SwiftUI

/// 今天组最后一行：平时是一行灰字「添加待办」，点开变成输入框。
///
/// 成功后不收起、不失焦——连着记几条是常态。失败时错误显示在本行下面，
/// 输入保留，用户改一改再回车即可，不用重新打字。
///
/// 提交中不禁用输入框：禁用会让系统收回焦点，之后没人再把它交回来。
/// 只在 onSubmit 里挡住重复提交即可。
struct TaskQuickAddRow: View {
    @Binding var isEditing: Bool
    @Binding var text: String
    let isSubmitting: Bool
    let errorMessage: String?
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool
    /// 回车时系统默认会收键盘、收回焦点，提交成功后 List 插入新行还会再收一次。
    /// 从回车到提交结束这段时间里，焦点一丢就要回来，否则「连着记几条」就断了。
    @State private var holdsFocus = false

    var body: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space4) {
            HStack(spacing: AimMetrics.space12) {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: AimMetrics.checkboxSize, height: AimMetrics.checkboxSize)
                } else {
                    Image(systemName: "plus")
                        .font(.body)
                        .foregroundStyle(Color.aimTextTertiary)
                        .frame(width: AimMetrics.checkboxSize)
                }

                if isEditing {
                    TextField("要做什么", text: $text)
                        .font(.body)
                        .foregroundStyle(Color.aimTextPrimary)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            guard !isSubmitting else { return }
                            holdsFocus = true
                            onSubmit()
                        }
                        .accessibilityLabel("添加待办")
                        .accessibilityIdentifier("home-quick-add-field")
                } else {
                    Button {
                        isEditing = true
                    } label: {
                        Text("添加待办")
                            .font(.body)
                            .foregroundStyle(Color.aimTextTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home-quick-add")
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.aimDanger)
                    .padding(.leading, AimMetrics.checkboxSize + AimMetrics.space12)
            }
        }
        .padding(.vertical, AimMetrics.space8)
        .onChange(of: isEditing) { _, editing in
            if !editing { holdsFocus = false }
            isFocused = editing
        }
        .onChange(of: isFocused) { _, focused in
            guard !focused else { return }
            if holdsFocus || isSubmitting {
                // 同一轮更新里直接设回去会被系统的收回覆盖，等下一轮再要。
                Task { @MainActor in isFocused = true }
                return
            }
            // 失焦且没在提交、也没输入内容时收起；有内容就留着，用户可能只是切了个 App。
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                isEditing = false
            }
        }
        .onChange(of: isSubmitting) { _, submitting in
            if !submitting { holdsFocus = false }
        }
    }
}
