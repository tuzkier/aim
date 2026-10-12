import Foundation

enum RecordType: Codable, CaseIterable, Sendable, Equatable {
    case symptom
    case checkup
    case note
    case question
    case checklist
    case knowledge
    case fetalMovement
    case memory
    case contraction
    case hospitalTrip
    case mood, epds
    case feeding, diaper, sleep
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
        case "memory": self = .memory
        case "contraction": self = .contraction
        case "hospital_trip": self = .hospitalTrip
        case "mood": self = .mood
        case "epds": self = .epds
        case "feeding": self = .feeding
        case "diaper": self = .diaper
        case "sleep": self = .sleep
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
        case .memory: return "memory"
        case .contraction: return "contraction"
        case .hospitalTrip: return "hospital_trip"
        case .mood: return "mood"
        case .epds: return "epds"
        case .feeding: return "feeding"
        case .diaper: return "diaper"
        case .sleep: return "sleep"
        case .unknown: return "unknown"
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    /// 能否在通用记录编辑器里修改。胎动记录由计数页生成，编辑器改不了它的计数数据。
    var canEditInComposer: Bool { ![.fetalMovement, .memory, .contraction, .hospitalTrip, .mood, .epds, .feeding, .diaper, .sleep].contains(self) }

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
    /// 四段文字都可选：AIM 从化验单读出来的报告常常只有数字，没有医生建议。
    /// 为 nil 时界面不显示那一行。
    let hospital: String?
    let examItems: String?
    let result: String?
    let doctorAdvice: String?
    /// 可计算的指标。四段文字画不出趋势，趋势要靠这里。
    var metrics: CheckupMetrics = CheckupMetrics()
    /// 七项指标之外的化验结果，原样记下。
    var otherItems: [CheckupOtherItem] = []

    /// 什么都没记。四段文字都可选之后，得靠这个挡住一份空报告。
    var isBlank: Bool {
        [hospital, examItems, result, doctorAdvice].allSatisfy {
            ($0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        } && metrics.isEmpty && otherItems.isEmpty
    }
}

/// 化验单上偏离参考范围的标记。
enum CheckupFlag: String, Codable, Sendable {
    case high, low, abnormal
}

/// 一项「其他化验」：数值按化验单原样存文字，如 `+-`、`12.1`。
struct CheckupOtherItem: Codable, Equatable, Sendable {
    var name: String
    var value: String
    var unit: String?
    var reference: String?
    var flag: CheckupFlag?
}

extension CheckupOtherItem {
    /// 写在扩展里以保留逐成员初始化器。不认识的标记按没有标记处理——
    /// 一个新标记不能让整份记录列表解不出来。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        value = try container.decode(String.self, forKey: .value)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        reference = try container.decodeIfPresent(String.self, forKey: .reference)
        flag = (try? container.decodeIfPresent(String.self, forKey: .flag)).flatMap(CheckupFlag.init(rawValue:))
    }
}

struct QuestionRecordData: Codable, Equatable, Sendable {
    let answered: Bool
    let answer: String?
    /// 从产检报告里攒出来的问题指回那份报告；手动加的问题没有。
    var reportID: UUID?
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

struct ContractionEntry: Codable, Equatable, Sendable {
    let start: Int      // 距第一次开始的秒数
    let duration: Int   // 持续秒数
}

enum ContractionPattern: String, Codable, Sendable { case early, approaching, go }

struct ContractionSummary: Codable, Equatable, Sendable {
    let count: Int
    let lastHourCount: Int
    let avgIntervalSeconds: Int?
    let avgDurationSeconds: Int
    let pattern: ContractionPattern
}

struct ContractionRecordData: Equatable, Sendable {
    let contractions: [ContractionEntry]
    /// 服务端算的；新建时客户端不发。
    var summary: ContractionSummary?
}

enum HospitalTripReason: String, CaseIterable, Sendable {
    case contractions, waterBroke = "water_broke", bleeding, fetalMovement = "fetal_movement", scheduled, other

    var displayName: String {
        switch self {
        case .contractions: "规律宫缩"
        case .waterBroke: "破水"
        case .bleeding: "出血"
        case .fetalMovement: "胎动少了"
        case .scheduled: "按医生安排入院"
        case .other: "其他"
        }
    }
}

struct HospitalTripRecordData: Equatable, Sendable {
    let reason: HospitalTripReason
    var contractionRecordID: UUID?
}

enum RecordStructuredData: Equatable, Sendable {
    case symptom(SymptomRecordData)
    case checkup(CheckupRecordData)
    case question(QuestionRecordData)
    case checklist(ChecklistRecordData)
    case knowledge(KnowledgeRecordData)
    case fetalMovement(FetalMovementRecordData)
    case memory(MemoryRecordData)
    case contraction(ContractionRecordData)
    case hospitalTrip(HospitalTripRecordData)
    case mood(MoodRecordData)
    case epds(EPDSRecordData)
    case feeding(BabyCareRecordData)
    case diaper(BabyCareRecordData)
    case sleep(BabyCareRecordData)
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

extension RecordItem {
    /// 编辑与删除权限，与后端 `assert_can_mutate` 一致：家庭可见的记录属于整个家庭，
    /// 任何成员都能改；仅自己可见的（以及看不懂的可见范围）只有作者能改。
    func isEditable(by accountID: UUID?) -> Bool {
        guard let accountID else { return false }
        if type == .mood || type == .epds { return accountID == authorAccountID }
        return visibility == .family || accountID == authorAccountID
    }

    /// 谁能看到这条记录，只由记下它的人决定。
    func canChangeVisibility(by accountID: UUID?) -> Bool {
        accountID != nil && accountID == authorAccountID
    }
}

struct RecordDraft: Equatable, Sendable {
    let type: RecordType
    let occurredAt: Date
    let visibility: RecordVisibility
    let title: String?
    let content: String?
    let structuredData: RecordStructuredData
    /// 已上传、要挂到这条新记录上的图片。只在新建时发送：后端更新记录的接口不收它。
    var attachmentIDs: [UUID] = []
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
