import Foundation

// Generated boundary snapshot from contracts/public-api/openapi.json.
// Feature code must use the domain models in BusinessRepository.swift instead.
struct APITaskDTO: Codable, Sendable {
    let id: UUID
    let planID: UUID
    let pregnancyID: UUID
    let title: String
    let description: String?
    let status: String
    let sourceType: String
    let sourceID: String?
    let changedByActorType: String
    let changedByActorID: UUID?
    let version: Int
    let scheduledFor: Date?
    let dueAt: Date?
    let assignedMemberID: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case planID = "plan_id"
        case pregnancyID = "pregnancy_id"
        case title, description, status
        case sourceType = "source_type"
        case sourceID = "source_id"
        case changedByActorType = "changed_by_actor_type"
        case changedByActorID = "changed_by_actor_id"
        case version
        case scheduledFor = "scheduled_for"
        case dueAt = "due_at"
        case assignedMemberID = "assigned_member_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct APITodayDTO: Codable, Sendable {
    let pregnancyID: UUID
    let asOf: Date
    let gestationalAge: APIGestationalAgeTodayDTO
    let priorityTask: APITaskDTO?
    let upcomingTasks: [APITaskDTO]
    let agentStatus: [String: AnyCodable]
    let familyTaskCounts: [APIFamilyTaskCountDTO]

    enum CodingKeys: String, CodingKey {
        case pregnancyID = "pregnancy_id"
        case asOf = "as_of"
        case gestationalAge = "gestational_age"
        case priorityTask = "priority_task"
        case upcomingTasks = "upcoming_tasks"
        case agentStatus = "agent_status"
        case familyTaskCounts = "family_task_counts"
    }
}

struct APIPlanDTO: Codable, Sendable {
    let id: UUID
    let pregnancyID: UUID
    let version: Int
    let createdAt: Date
    let updatedAt: Date
    let tasks: [APITaskDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case pregnancyID = "pregnancy_id"
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case tasks
    }
}

struct APIFamilyDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let createdBy: UUID
    let createdAt: Date
    let members: [APIFamilyMemberDTO]
    /// 只有读取家庭时才给；改名等接口的返回里没有。
    let invitations: [APIFamilyInvitationDTO]?

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdBy = "created_by"
        case createdAt = "created_at"
        case members, invitations
    }
}

struct APIFamilyInvitationDTO: Codable, Sendable {
    let id: UUID
    let phoneMasked: String
    let role: String
    let invitedBy: UUID
    let expiresAt: Date
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, role, status
        case phoneMasked = "phone_masked"
        case invitedBy = "invited_by"
        case expiresAt = "expires_at"
    }
}

struct APIFamilyMemberDTO: Codable, Sendable {
    let accountID: UUID
    let role: String
    /// 少声明一个字段，数据就在两个方向上静默丢失——服务端存了，客户端看不见。
    let nickname: String?
    let status: String
    let invitedAt: Date?
    let joinedAt: Date?
    let isAdmin: Bool?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case role, nickname, status
        case invitedAt = "invited_at"
        case joinedAt = "joined_at"
        case isAdmin = "is_admin"
    }
}

struct APIGestationalAgeTodayDTO: Codable, Sendable {
    let weeks: Int
    let days: Int
}

struct APIFamilyTaskCountDTO: Codable, Sendable {
    let assignedMemberID: UUID?
    let openCount: Int

    enum CodingKeys: String, CodingKey {
        case assignedMemberID = "assigned_member_id"
        case openCount = "open_count"
    }
}

struct APIExpectedVersionDTO: Codable, Sendable {
    let expectedVersion: Int

    enum CodingKeys: String, CodingKey {
        case expectedVersion = "expected_version"
    }
}

struct APIDelayTaskDTO: Codable, Sendable {
    let expectedVersion: Int
    let dueAt: Date

    enum CodingKeys: String, CodingKey {
        case expectedVersion = "expected_version"
        case dueAt = "due_at"
    }
}

struct APIScheduleTaskDTO: Codable, Sendable {
    let expectedVersion: Int
    let scheduledFor: Date

    enum CodingKeys: String, CodingKey {
        case expectedVersion = "expected_version"
        case scheduledFor = "scheduled_for"
    }
}

struct APIAssignTaskDTO: Codable, Sendable {
    let expectedVersion: Int
    let assignedMemberID: UUID?

    enum CodingKeys: String, CodingKey {
        case expectedVersion = "expected_version"
        case assignedMemberID = "assigned_member_id"
    }
}

struct APIRecordDTO: Codable, Sendable {
    let id: UUID
    let pregnancyID: UUID
    let familyID: UUID
    let authorAccountID: UUID
    let type: RecordType
    let occurredAt: Date
    let visibility: RecordVisibility
    let title: String?
    let content: String?
    let structuredData: APIRecordStructuredDataDTO
    let attachmentRefs: [String]
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case pregnancyID = "pregnancy_id"
        case familyID = "family_id"
        case authorAccountID = "author_account_id"
        case type
        case occurredAt = "occurred_at"
        case visibility, title, content
        case structuredData = "structured_data"
        case attachmentRefs = "attachment_refs"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct APIRecordListDTO: Codable, Sendable {
    let records: [APIRecordDTO]
}

struct APIRecordStructuredDataDTO: Codable, Sendable {
    let symptoms: [String]?
    let severity: Int?
    let note: String?
    let hospital: String?
    let examItems: String?
    let result: String?
    let doctorAdvice: String?
    /// 可计算的产检指标。缺了它，趋势条与「本周关注」的血压规则永远没有数据。
    let metrics: CheckupMetrics?
    let otherItems: [CheckupOtherItem]?
    let answered: Bool?
    let answer: String?
    /// 小写标准写法的 UUID 字符串。服务端按字符串配对，只认小写。
    let reportID: String?
    let collection: String?
    let itemID: String?
    let done: Bool?
    let category: String?
    let form: String?
    let ingredients: [String]?
    let steps: [String]?
    let verdict: String?
    let reason: String?
    let body: String?
    let purposes: [String]?
    let durationSeconds: Int?
    let count: Int?
    let target: Int?
    let outcome: String?
    let taps: [Int]?
    /// 只在为 true 时编码（可选值为 nil 时不输出），解码缺省按 false。
    let reportedLess: Bool?
    let kind: String?
    let text: String?
    let contractions: [ContractionEntry]?
    let summary: ContractionSummaryDTO?
    /// 去医院记录关联的宫缩计时，小写标准 UUID 字符串。
    let contractionRecordID: String?
    let mood: Int?
    let tags: [String]?
    let version: String?
    let answers: [Int]?
    let period: String?
    let score: Int?
    let item10: Int?
    let supportLevel: String?
    let babyID: String?
    let mode: String?
    let volumeMl: Double?
    let durationMinutes: Int?
    let side: String?
    let endedAt: Date?

    init(
        symptoms: [String]? = nil,
        severity: Int? = nil,
        note: String? = nil,
        hospital: String? = nil,
        examItems: String? = nil,
        result: String? = nil,
        doctorAdvice: String? = nil,
        metrics: CheckupMetrics? = nil,
        otherItems: [CheckupOtherItem]? = nil,
        answered: Bool? = nil,
        answer: String? = nil,
        reportID: String? = nil,
        collection: String? = nil,
        itemID: String? = nil,
        done: Bool? = nil,
        category: String? = nil,
        form: String? = nil,
        ingredients: [String]? = nil,
        steps: [String]? = nil,
        verdict: String? = nil,
        reason: String? = nil,
        body: String? = nil,
        purposes: [String]? = nil,
        durationSeconds: Int? = nil,
        count: Int? = nil,
        target: Int? = nil,
        outcome: String? = nil,
        taps: [Int]? = nil,
        reportedLess: Bool? = nil,
        kind: String? = nil,
        text: String? = nil,
        contractions: [ContractionEntry]? = nil,
        summary: ContractionSummaryDTO? = nil,
        contractionRecordID: String? = nil,
        mood: Int? = nil, tags: [String]? = nil, version: String? = nil, answers: [Int]? = nil,
        period: String? = nil, score: Int? = nil, item10: Int? = nil, supportLevel: String? = nil,
        babyID: String? = nil, mode: String? = nil, volumeMl: Double? = nil, durationMinutes: Int? = nil, side: String? = nil, endedAt: Date? = nil
    ) {
        self.symptoms = symptoms
        self.severity = severity
        self.note = note
        self.hospital = hospital
        self.examItems = examItems
        self.result = result
        self.doctorAdvice = doctorAdvice
        self.metrics = metrics
        self.otherItems = otherItems
        self.answered = answered
        self.answer = answer
        self.reportID = reportID
        self.collection = collection
        self.itemID = itemID
        self.done = done
        self.category = category
        self.form = form
        self.ingredients = ingredients
        self.steps = steps
        self.verdict = verdict
        self.reason = reason
        self.body = body
        self.purposes = purposes
        self.durationSeconds = durationSeconds
        self.count = count
        self.target = target
        self.outcome = outcome
        self.taps = taps
        self.reportedLess = reportedLess
        self.kind = kind
        self.text = text
        self.contractions = contractions
        self.summary = summary
        self.contractionRecordID = contractionRecordID
        self.mood = mood; self.tags = tags; self.version = version; self.answers = answers
        self.period = period; self.score = score; self.item10 = item10; self.supportLevel = supportLevel
        self.babyID = babyID; self.mode = mode; self.volumeMl = volumeMl; self.durationMinutes = durationMinutes; self.side = side; self.endedAt = endedAt
    }

    enum CodingKeys: String, CodingKey {
        case symptoms, severity, note, hospital, result, metrics
        case examItems = "exam_items"
        case doctorAdvice = "doctor_advice"
        case otherItems = "other_items"
        case answered, answer, collection, done
        case reportID = "report_id"
        case category, form, ingredients, steps, verdict, reason, body, purposes
        case itemID = "item_id"
        case count, target, outcome, taps
        case kind, text
        case durationSeconds = "duration_seconds"
        case reportedLess = "reported_less"
        case contractions, summary
        case contractionRecordID = "contraction_record_id"
        case mood, tags, version, answers, period, score
        case item10 = "item_10"
        case supportLevel = "support_level"
        case babyID = "baby_id", volumeMl = "volume_ml", durationMinutes = "duration_minutes", endedAt = "ended_at"
        case mode, side
    }

    func recordData(for type: RecordType) -> RecordStructuredData {
        switch type {
        case .feeding, .diaper, .sleep:
            guard let raw = babyID, let id = UUID(uuidString: raw) else { return .unknown }
            let data = BabyCareRecordData(babyID: id, mode: mode, volumeMl: volumeMl, durationMinutes: durationMinutes,
                side: side, diaperKind: kind, endedAt: endedAt, durationSeconds: durationSeconds)
            if type == .feeding { return .feeding(data) }
            if type == .diaper { return .diaper(data) }
            return .sleep(data)
        case .mood:
            guard let mood, (1...5).contains(mood) else { return .unknown }
            return .mood(MoodRecordData(mood: mood, tags: tags ?? []))
        case .epds:
            guard let version, let answers, answers.count == 10 else { return .unknown }
            return .epds(EPDSRecordData(version: version, answers: answers, period: EmotionalPeriod(rawValue: period ?? "manual") ?? .manual, score: score, item10: item10, supportLevel: supportLevel.flatMap(EmotionalSupportLevel.init(rawValue:))))
        case .memory:
            guard let kind, let text else { return .unknown }
            return .memory(MemoryRecordData(kind: MemoryKind(rawValue: kind) ?? .unknown, text: text))
        case .symptom:
            guard let symptoms, let severity else { return .unknown }
            return .symptom(SymptomRecordData(symptoms: symptoms, severity: severity, note: note))
        case .checkup:
            // 四段文字都可选：只有指标的报告也是一份完整的产检记录。
            return .checkup(CheckupRecordData(
                hospital: hospital, examItems: examItems, result: result,
                doctorAdvice: doctorAdvice, metrics: metrics ?? CheckupMetrics(),
                otherItems: otherItems ?? []))
        case .question:
            return .question(QuestionRecordData(
                answered: answered ?? false, answer: answer,
                reportID: reportID.flatMap(UUID.init(uuidString:))))
        case .checklist:
            guard let collection, let itemID else { return .unknown }
            return .checklist(ChecklistRecordData(collection: collection, itemID: itemID, done: done ?? false))
        case .knowledge:
            guard let category, let form else { return .unknown }
            return .knowledge(KnowledgeRecordData(
                category: category,
                form: KnowledgeForm(rawValue: form),
                ingredients: ingredients,
                steps: steps,
                verdict: verdict.map(FoodVerdict.init(rawValue:)),
                reason: reason,
                body: body,
                note: note,
                purposes: purposes
            ))
        case .fetalMovement:
            guard let durationSeconds, let count, let target, let taps,
                  let outcome = outcome.flatMap(FetalMovementOutcome.init(rawValue:)) else { return .unknown }
            return .fetalMovement(FetalMovementRecordData(
                durationSeconds: durationSeconds, count: count, target: target, outcome: outcome, taps: taps,
                reportedLess: reportedLess ?? false))
        case .contraction:
            guard let contractions, !contractions.isEmpty else { return .unknown }
            return .contraction(ContractionRecordData(contractions: contractions, summary: summary?.model))
        case .hospitalTrip:
            guard let reason, let value = HospitalTripReason(rawValue: reason) else { return .unknown }
            return .hospitalTrip(HospitalTripRecordData(
                reason: value, contractionRecordID: contractionRecordID.flatMap(UUID.init(uuidString:))))
        case .note:
            return .note
        case .unknown:
            return .unknown
        }
    }

    init(recordData: RecordStructuredData) {
        switch recordData {
        case let .feeding(data):
            self.init(babyID: data.babyID.uuidString.lowercased(), mode: data.mode,
                volumeMl: data.volumeMl, durationMinutes: data.durationMinutes, side: data.side)
        case let .diaper(data):
            self.init(kind: data.diaperKind, babyID: data.babyID.uuidString.lowercased())
        case let .sleep(data):
            self.init(babyID: data.babyID.uuidString.lowercased(), endedAt: data.endedAt)
        case let .mood(data):
            self.init(mood: data.mood, tags: data.tags)
        case let .epds(data):
            self.init(version: data.version, answers: data.answers, period: data.period.rawValue)
        case let .memory(data):
            self.init(kind: data.kind.rawValue, text: data.text)
        case let .symptom(data):
            self.init(symptoms: data.symptoms, severity: data.severity, note: data.note)
        case let .checkup(data):
            // 空文字段不发：没填就是没有，而不是一段空串。
            self.init(
                hospital: data.hospital?.nilIfBlank, examItems: data.examItems?.nilIfBlank,
                result: data.result?.nilIfBlank, doctorAdvice: data.doctorAdvice?.nilIfBlank,
                // 没测的指标不发空对象，避免把 null 当成 0。
                metrics: data.metrics.isEmpty ? nil : data.metrics,
                otherItems: data.otherItems.isEmpty ? nil : data.otherItems)
        case let .question(data):
            self.init(
                answered: data.answered, answer: data.answer,
                reportID: data.reportID?.uuidString.lowercased())
        case let .checklist(data):
            self.init(collection: data.collection, itemID: data.itemID, done: data.done)
        case let .knowledge(data):
            self.init(
                note: data.note, category: data.category, form: data.form.rawValue,
                ingredients: data.ingredients, steps: data.steps,
                verdict: data.verdict?.rawValue, reason: data.reason, body: data.body,
                purposes: data.purposes
            )
        case let .fetalMovement(data):
            self.init(durationSeconds: data.durationSeconds, count: data.count, target: data.target,
                      outcome: data.outcome.rawValue, taps: data.taps,
                      reportedLess: data.reportedLess ? true : nil)
        case let .contraction(data):
            // summary 由服务端计算，不发。
            self.init(contractions: data.contractions)
        case let .hospitalTrip(data):
            self.init(reason: data.reason.rawValue,
                      contractionRecordID: data.contractionRecordID?.uuidString.lowercased())
        case .note, .unknown:
            self.init()
        }
    }
}

/// 宫缩计时摘要的接口形状：把 snake_case 键名映射到 ContractionSummary。
struct ContractionSummaryDTO: Codable, Sendable {
    let count: Int
    let lastHourCount: Int
    let avgIntervalSeconds: Int?
    let avgDurationSeconds: Int
    let pattern: String

    enum CodingKeys: String, CodingKey {
        case count, pattern
        case lastHourCount = "last_hour_count"
        case avgIntervalSeconds = "avg_interval_seconds"
        case avgDurationSeconds = "avg_duration_seconds"
    }

    var model: ContractionSummary? {
        ContractionPattern(rawValue: pattern).map {
            ContractionSummary(count: count, lastHourCount: lastHourCount,
                               avgIntervalSeconds: avgIntervalSeconds,
                               avgDurationSeconds: avgDurationSeconds, pattern: $0)
        }
    }
}

struct APICreateRecordDTO: Encodable, Sendable {
    let type: RecordType
    let occurredAt: Date
    let visibility: RecordVisibility
    let title: String?
    let content: String?
    let structuredData: APIRecordStructuredDataDTO
    /// 没有图片时为 nil，不发这个字段。
    let attachmentIDs: [UUID]?

    init(draft: RecordDraft) {
        type = draft.type
        occurredAt = draft.occurredAt
        visibility = draft.visibility
        title = draft.title
        content = draft.content
        structuredData = APIRecordStructuredDataDTO(recordData: draft.structuredData)
        attachmentIDs = draft.attachmentIDs.isEmpty ? nil : draft.attachmentIDs
    }

    enum CodingKeys: String, CodingKey {
        case type
        case occurredAt = "occurred_at"
        case visibility, title, content
        case structuredData = "structured_data"
        case attachmentIDs = "attachment_ids"
    }
}

/// 不带 attachment_ids：后端 PATCH 记录的接口不收它，图片只能在新建时挂上。
struct APIUpdateRecordDTO: Encodable, Sendable {
    let occurredAt: Date
    let visibility: RecordVisibility
    let title: String?
    let content: String?
    let structuredData: APIRecordStructuredDataDTO

    init(draft: RecordDraft) {
        occurredAt = draft.occurredAt
        visibility = draft.visibility
        title = draft.title
        content = draft.content
        structuredData = APIRecordStructuredDataDTO(recordData: draft.structuredData)
    }

    enum CodingKeys: String, CodingKey {
        case occurredAt = "occurred_at"
        case visibility, title, content
        case structuredData = "structured_data"
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

struct AnyCodable: Codable, Sendable, Equatable {
    let value: String

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let value = try? container.decode(String.self) {
            self.value = value
        } else {
            self.value = ""
        }
    }

    init(value: String) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
