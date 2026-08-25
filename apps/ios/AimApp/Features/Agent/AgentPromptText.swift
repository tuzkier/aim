import Foundation

/// 发给模型的文本和给用户看的文本不是一回事。
///
/// `AgentStore.requestMessage(for:)` 会在提问前面拼当前页面的上下文。那段是给
/// 模型看的；重放历史对话时若原样显示，用户会看到自己「说」了一堆没说过的话。
enum AgentPromptText {
    private static let marker = "用户问题："

    static func userVisible(_ sentText: String) -> String {
        guard let range = sentText.range(of: marker, options: .backwards) else {
            return sentText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(sentText[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
