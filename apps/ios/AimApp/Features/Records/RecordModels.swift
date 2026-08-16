import Foundation

enum RecordType: Codable, CaseIterable, Sendable, Equatable {
    case symptom
    case checkup
    case note
    case unknown

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "symptom": self = .symptom
        case "checkup": self = .checkup
        case "note": self = .note
        default: self = .unknown
        }
    }

    var rawValue: String {
        switch self {
        case .symptom: return "symptom"
        case .checkup: return "checkup"
        case .note: return "note"
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
}

enum RecordStructuredData: Equatable, Sendable {
    case symptom(SymptomRecordData)
    case checkup(CheckupRecordData)
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
