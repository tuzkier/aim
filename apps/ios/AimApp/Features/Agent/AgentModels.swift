import Foundation

enum AgentSheetState: Equatable {
    case idle
    case streaming
    case awaitingApproval(EveInputRequest)
    case applied
    case failed(String)
}

struct AgentContext: Equatable, Sendable {
    let title: String
    let summary: String

    var prompt: String {
        "当前页面：\(title)\n当前页面摘要：\(summary)"
    }
}

struct AgentMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isUser: Bool
}

enum AgentResponseText {
    static func clean(_ text: String) -> String {
        var cleaned = text
        for tag in ["think", "analysis", "reasoning"] {
            let pattern = "(?is)<" + tag + "\\b[^>]*>.*?</" + tag + ">"
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
