import ExyteChat

enum AgentChatAdapter {
    private static let currentUser = User(
        id: "aim-user",
        name: "我",
        avatarURL: nil,
        isCurrentUser: true
    )

    private static let agentUser = User(
        id: "aim-agent",
        name: "Aim",
        avatarURL: nil,
        isCurrentUser: false
    )

    static func messages(from source: [AgentMessage]) -> [ExyteChat.Message] {
        source.map { message in
            ExyteChat.Message(
                id: message.id.uuidString,
                user: message.isUser ? currentUser : agentUser,
                status: .sent,
                text: message.text
            )
        }
    }
}
