import Foundation

enum AgentSheetState: Equatable {
    case idle
    case streaming
    case awaitingApproval(EveInputRequest)
    case applied
    case failed(String)
}

struct AgentMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isUser: Bool
}
