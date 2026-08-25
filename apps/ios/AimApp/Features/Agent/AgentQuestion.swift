import Foundation

/// Agent 的一次反问。
///
/// 和「写操作待批准」共用 `input.requested` 事件，但两者要走完全不同的界面：
/// 批准是权限边界，必须停下来在浮层里逐项确认；反问只是对话的一部分，
/// 打断成模态卡反而让人没法回答。
///
/// 判据取自线上抓到的两条真实报文：
///
/// | | 提问 | 写操作批准 |
/// |---|---|---|
/// | `kind` | `question` | `tool-approval` |
/// | `action.toolName` | `ask_question` | `create_knowledge` |
/// | `allowFreeform` | `true` | `false` |
/// | `options` | 不存在 | `[approve, cancel]` |
///
/// 注意提问同样带 `action`，所以「没有工具就是提问」这条看似自然的规则是错的。
/// 认 `kind`，并且额外要求：带 action 时必须是 `ask_question`。这样即使哪天
/// 某个写操作漏发 `kind`（解码会兜底成 "question"），它也不会被误判成提问
/// 而绕过确认——权限边界宁可错判成要确认，不能错判成不用确认。
struct AgentQuestion: Equatable, Identifiable {
    static let askTool = "ask_question"

    let requestID: String
    let prompt: String
    let options: [EveInputOption]
    /// 能不能直接打字回答。线上的提问都是 true；为 false 时只能点选项。
    let allowsFreeform: Bool

    var id: String { requestID }

    init?(request: EveInputRequest) {
        guard request.kind == "question" else { return nil }
        if let toolName = request.toolName, toolName != Self.askTool { return nil }

        let prompt = (request.prompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }

        requestID = request.requestID
        self.prompt = prompt
        options = request.options
        allowsFreeform = request.allowFreeform
    }
}
