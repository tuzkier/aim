import Foundation

enum RecordType: Codable, CaseIterable, Sendable, Equatable {
    case symptom
    case checkup
    case note
    case question
    case checklist
    case knowledge
    case fetalMovement
    case unknown

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "symptom": self = .symptom
        case "checkup": self = .checkup
        case "note": self = .note
        case "question": self = .question
        case "checklist": self = .checklist
        case "knowledge": self = .knowledge
        case "fetal_movement": self = .fetalMovement
        default: self = .unknown
        }
    }

    var rawValue: String {
        switch self {
        case .symptom: return "symptom"
        case .checkup: return "checkup"
        case .note: return "note"
        case .question: return "question"
        case .checklist: return "checklist"
        case .knowledge: return "knowledge"
        case .fetalMovement: return "fetal_movement"
        case .unknown: return "unknown"
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    /// 能否在通用记录编辑器里修改。胎动记录由计数页生成，编辑器改不了它的计数数据。
    var canEditInComposer: Bool { self != .fetalMovement }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum RecordVisibility: Codable, CaseIterable, Sendable, Equatable {
    case family
    case `private`
    case unknown

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "family": self = .family
        case "private": self = .private
        default: self = .unknown
        }
    }

    var rawValue: String {
        switch self {
        case .family: return "family"
        case .private: return "private"
        case .unknown: return "unknown"
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct SymptomRecordData: Codable, Equatable, Sendable {
    let symptoms: [String]
    let severity: Int
    let note: String?
}

struct CheckupRecordData: Codable, Equatable, Sendable {
    let hospital: String
    let examItems: String
    let result: String
    let doctorAdvice: String
    /// 可计算的指标。四段文字画不出趋势，趋势要靠这里。
    var metrics: CheckupMetrics = CheckupMetrics()
}

struct QuestionRecordData: Codable, Equatable, Sendable {
    let answered: Bool
    let answer: String?
}

enum FetalMovementOutcome: String, Codable, Sendable {
    /// 数到 10 次。
    case reached
    /// 满 2 小时不足 10 次。
    case under
    /// 中途手动结束。
    case stopped
}

/// 一次「数到 10 次」胎动计数。开始时间就是记录的 occurredAt。
struct FetalMovementRecordData: Codable, Equatable, Sendable {
    let durationSeconds: Int
    let count: Int
    let target: Int
    let outcome: FetalMovementOutcome
    /// 每次计数距开始的秒数。
    let taps: [Int]
    /// 计数中点了「胎动明显少了？」。这是要留档的就医信号，与结果无关。
    var reportedLess = false
}

extension FetalMovementRecordData {
    /// 写在扩展里以保留逐成员初始化器。旧数据没有 reportedLess，按没报告处理。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        count = try container.decode(Int.self, forKey: .count)
        target = try container.decode(Int.self, forKey: .target)
        outcome = try container.decode(FetalMovementOutcome.self, forKey: .outcome)
        taps = try container.decode([Int].self, forKey: .taps)
        reportedLess = try container.decodeIfPresent(Bool.self, forKey: .reportedLess) ?? false
    }
}

enum FetalMovementFormat {
    /// 「不到 1 分钟」「32 分钟」「1 小时 15 分钟」「2 小时」。分钟向上取整：
    /// 32 分 1 秒显示 33 分钟，避免把慢的说成快的。
    static func duration(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "不到 1 分钟" }
        let minutes = (seconds + 59) / 60
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(minutes) 分钟" }
        return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分钟"
    }

    static func summary(_ data: FetalMovementRecordData) -> String {
        let base = switch data.outcome {
        case .reached: "\(data.count) 次 · \(duration(data.durationSeconds))"
        case .under: "\(duration(data.durationSeconds)) \(data.count) 次 · 不足 \(data.target) 次"
        case .stopped: "\(data.count) 次 · \(duration(data.durationSeconds)) · 未数完"
        }
        return data.reportedLess ? base + " · 感觉胎动少了" : base
    }
}

/// 办事指南与待产准备共用：内容库给条目，这里只存勾选状态。
struct ChecklistRecordData: Codable, Equatable, Sendable {
    let collection: String
    let itemID: String
    let done: Bool

    enum CodingKeys: String, CodingKey {
        case collection
        case itemID = "item_id"
        case done
    }
}

enum RecordStructuredData: Equatable, Sendable {
    case symptom(SymptomRecordData)
    case checkup(CheckupRecordData)
    case question(QuestionRecordData)
    case checklist(ChecklistRecordData)
    case knowledge(KnowledgeRecordData)
    case fetalMovement(FetalMovementRecordData)
    case note
    case unknown
}

struct RecordItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let pregnancyID: UUID
    let familyID: UUID
    let authorAccountID: UUID
    let type: RecordType
    let occurredAt: Date
    let visibility: RecordVisibility
    let title: String?
    let content: String?
    let structuredData: RecordStructuredData
    let attachmentRefs: [String]
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID,
        pregnancyID: UUID,
        familyID: UUID,
        authorAccountID: UUID,
        type: RecordType,
        occurredAt: Date,
        visibility: RecordVisibility,
        title: String?,
        content: String?,
        structuredData: RecordStructuredData,
        attachmentRefs: [String],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.pregnancyID = pregnancyID
        self.familyID = familyID
        self.authorAccountID = authorAccountID
        self.type = type
        self.occurredAt = occurredAt
        self.visibility = visibility
        self.title = title
        self.content = content
        self.structuredData = structuredData
        self.attachmentRefs = attachmentRefs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(dto: APIRecordDTO) {
        id = dto.id
        pregnancyID = dto.pregnancyID
        familyID = dto.familyID
        authorAccountID = dto.authorAccountID
        type = dto.type
        occurredAt = dto.occurredAt
        visibility = dto.visibility
        title = dto.title
        content = dto.content
        structuredData = dto.structuredData.recordData(for: dto.type)
        attachmentRefs = dto.attachmentRefs
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
    }
}

struct RecordDraft: Equatable, Sendable {
    let type: RecordType
    let occurredAt: Date
    let visibility: RecordVisibility
    let title: String?
    let content: String?
    let structuredData: RecordStructuredData
}

struct RecordSnapshot: Equatable, Sendable {
    let records: [RecordItem]

    init(records: [RecordItem]) {
        self.records = records.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
            return $0.createdAt > $1.createdAt
        }
    }
}
