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
