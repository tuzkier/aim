import Foundation

/// 一段 AIM 对话在列表里的样子。内容不在这里——它留在 Eve，
/// 需要时用 `eveSessionID` 重放回来。
struct AgentSessionSummary: Identifiable, Equatable, Sendable, Decodable {
    let id: UUID
    let eveSessionID: String
    let title: String
    let lastActiveAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case eveSessionID = "eve_session_id"
        case title
        case lastActiveAt = "last_active_at"
    }

    /// 打开 AIM 时要接着聊的那一段。
    static func mostRecent(of sessions: [AgentSessionSummary]) -> AgentSessionSummary? {
        sessions.max { $0.lastActiveAt < $1.lastActiveAt }
    }
}

/// 从第一句提问里取会话标题。
///
/// 不额外调模型生成摘要：多一次调用、多一处延迟和失败点，而第一句话通常已经
/// 说明了这段对话在讲什么。
enum AgentSessionTitle {
    static let maxLength = 40
    static let fallback = "新对话"

    /// `AgentStore.requestMessage(for:)` 会在提问前面拼当前页面的上下文。
    /// 那段是给模型看的，不该变成用户看到的标题。
    private static let userQuestionMarker = "用户问题："

    static func from(_ sentText: String) -> String {
        var text = sentText
        if let range = text.range(of: userQuestionMarker, options: .backwards) {
            text = String(text[range.upperBound...])
        }
        // 列表里一行放不下第二行，只取第一行。
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        guard trimmed.count > maxLength else { return trimmed }
        // 截断要看得出来是截断，否则读起来像话说了一半。
        return String(trimmed.prefix(maxLength - 1)) + "…"
    }
}
