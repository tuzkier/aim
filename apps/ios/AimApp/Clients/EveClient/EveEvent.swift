import Foundation

enum EveEventType: Equatable, Sendable {
    case sessionStarted
    case turnStarted
    case turnCompleted
    case sessionWaiting
    case sessionCompleted
    case messageReceived
    case messageAppended
    case messageCompleted
    case actionsRequested
    case actionResult
    case inputRequested
    case approvalSettled
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "session.started": self = .sessionStarted
        case "turn.started": self = .turnStarted
        case "turn.completed": self = .turnCompleted
        case "session.waiting": self = .sessionWaiting
        case "session.completed": self = .sessionCompleted
        case "message.received": self = .messageReceived
        case "message.appended": self = .messageAppended
        case "message.completed": self = .messageCompleted
        case "actions.requested": self = .actionsRequested
        case "action.result": self = .actionResult
        case "input.requested": self = .inputRequested
        case "approval.settled": self = .approvalSettled
        default: self = .unknown(rawValue)
        }
    }
}

struct EveEvent: Equatable, Sendable {
    let type: EveEventType
    let rawType: String
    let eventID: String?
    let streamIndex: Int
    let data: Data

    var inputRequests: [EveInputRequest] {
        guard type == .inputRequested else { return [] }
        return (try? JSONDecoder().decode(EveInputRequestedPayload.self, from: data).requests) ?? []
    }

    /// 这一轮到此为止，服务端不会再吐字节了。
    ///
    /// 不认这个标记就会一直挂在流上等下一条事件，60 秒后 URLSession 抛
    /// `NSURLErrorTimedOut`，界面上冒出一句「The request timed out.」——
    /// 回答明明已经正常显示，却在一分钟后被一条假错误覆盖掉。
    var isTerminal: Bool {
        switch type {
        case .sessionWaiting, .sessionCompleted: true
        default: false
        }
    }

    var continuationToken: String? {
        guard type == .sessionWaiting else { return nil }
        return try? JSONDecoder().decode(EveSessionWaitingPayload.self, from: data).continuationToken
    }
}

struct EveInputRequest: Codable, Equatable, Sendable, Identifiable {
    let requestID: String
    let kind: String
    let prompt: String?
    let options: [EveInputOption]
    let toolName: String?
    let toolInput: [String: JSONValue]?
    let changes: [EveChangeDTO]?
    let qualifier: String?
    /// Eve 说这次提问能不能自由作答。提问是 true，写操作批准是 false。
    let allowFreeform: Bool

    var id: String { requestID }

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case kind, prompt, options, action, changes, qualifier, allowFreeform
    }

    init(
        requestID: String,
        kind: String,
        prompt: String?,
        options: [EveInputOption],
        toolName: String?,
        toolInput: [String: JSONValue]? = nil,
        changes: [EveChangeDTO]? = nil,
        qualifier: String? = nil,
        allowFreeform: Bool = false
    ) {
        self.allowFreeform = allowFreeform
        self.requestID = requestID
        self.kind = kind
        self.prompt = prompt
        self.options = options
        self.toolName = toolName
        self.toolInput = toolInput
        self.changes = changes
        self.qualifier = qualifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(String.self, forKey: .requestID)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "question"
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        options = try container.decodeIfPresent([EveInputOption].self, forKey: .options) ?? []
        if let action = try container.decodeIfPresent(EveToolCallAction.self, forKey: .action) {
            toolName = action.toolName
            toolInput = action.input
        } else {
            toolName = nil
            toolInput = nil
        }
        changes = try container.decodeIfPresent([EveChangeDTO].self, forKey: .changes)
        qualifier = try container.decodeIfPresent(String.self, forKey: .qualifier)
        allowFreeform = try container.decodeIfPresent(Bool.self, forKey: .allowFreeform) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encode(options, forKey: .options)
        try container.encodeIfPresent(changes, forKey: .changes)
        try container.encodeIfPresent(qualifier, forKey: .qualifier)
    }
}

struct EveChangeDTO: Codable, Equatable, Sendable {
    let field: String
    let before: String?
    let after: String
    let symbol: String?
}

struct EveInputOption: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
}

struct EveInputResponse: Codable, Sendable {
    let requestID: String
    let optionID: String?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case optionID = "optionId"
        case text
    }
}

struct EveInputRequestedPayload: Codable, Sendable {
    let requests: [EveInputRequest]
}

struct EveSessionWaitingPayload: Codable, Sendable {
    let continuationToken: String?
    let wait: String?
}

private struct EveToolCallAction: Decodable, Sendable {
    let toolName: String
    /// 工具入参。审批卡要靠它渲染「将要写入的内容长什么样」，
    /// 而不是只显示 Eve 默认的英文提示。
    let input: [String: JSONValue]?
}

/// 只为读取工具入参而存在的最小 JSON 表示。
enum JSONValue: Decodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .null }
    }

    var stringValue: String? { if case let .string(v) = self { return v }; return nil }
    var stringArray: [String]? {
        guard case let .array(items) = self else { return nil }
        let strings = items.compactMap(\.stringValue)
        return strings.count == items.count ? strings : nil
    }
}

struct EveNDJSONDecoder: Sendable {
    private var buffer = Data()
    private var nextIndex = 0
    private var seenEventIDs = Set<String>()

    init(startIndex: Int = 0) {
        nextIndex = max(0, startIndex)
    }

    mutating func append(_ chunk: Data) throws -> [EveEvent] {
        buffer.append(chunk)
        return try drainLines()
    }

    mutating func finish() throws -> [EveEvent] {
        guard !buffer.isEmpty else { return [] }
        let tail = buffer
        buffer.removeAll(keepingCapacity: false)
        return try decodeLine(tail)
    }

    private mutating func drainLines() throws -> [EveEvent] {
        var events: [EveEvent] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            events.append(contentsOf: try decodeLine(line))
        }
        return events
    }

    private mutating func decodeLine(_ line: Data) throws -> [EveEvent] {
        let trimmed = line.drop(while: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D })
        guard !trimmed.isEmpty else { return [] }
        let envelope = try JSONDecoder().decode(EveWireEnvelope.self, from: Data(trimmed))
        if let eventID = envelope.meta?.id, seenEventIDs.contains(eventID) { return [] }
        if let eventID = envelope.meta?.id { seenEventIDs.insert(eventID) }
        let data = try JSONEncoder().encode(envelope.data ?? .object([:]))
        defer { nextIndex += 1 }
        return [EveEvent(type: EveEventType(rawValue: envelope.type), rawType: envelope.type, eventID: envelope.meta?.id, streamIndex: nextIndex + 1, data: data)]
    }
}

private struct EveWireEnvelope: Codable, Sendable {
    let type: String
    let data: EveJSONValue?
    let meta: EveWireMeta?
}

private struct EveWireMeta: Codable, Sendable {
    let id: String?
}

private enum EveJSONValue: Codable, Sendable {
    case object([String: EveJSONValue])
    case array([EveJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode([String: EveJSONValue].self) { self = .object(value); return }
        if let value = try? container.decode([EveJSONValue].self) { self = .array(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        self = .number(try container.decode(Double.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private struct EveMessageReceived: Decodable {
    let message: String?
    let text: String?
}

extension EveEvent {
    /// 用户发的那句话。重放历史对话时要靠它还原提问——
    /// 实时发送时这句是客户端本地 append 的，事件里的这份没人用。
    var userMessageText: String? {
        guard type == .messageReceived,
              let payload = try? JSONDecoder().decode(EveMessageReceived.self, from: data)
        else { return nil }
        return payload.message ?? payload.text
    }
}
