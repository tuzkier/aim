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

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdBy = "created_by"
        case createdAt = "created_at"
        case members
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

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case role, nickname, status
        case invitedAt = "invited_at"
        case joinedAt = "joined_at"
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
    let answered: Bool?
    let answer: String?
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

    init(
        symptoms: [String]? = nil,
        severity: Int? = nil,
        note: String? = nil,
        hospital: String? = nil,
        examItems: String? = nil,
        result: String? = nil,
        doctorAdvice: String? = nil,
        metrics: CheckupMetrics? = nil,
        answered: Bool? = nil,
        answer: String? = nil,
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
        purposes: [String]? = nil
    ) {
        self.symptoms = symptoms
        self.severity = severity
        self.note = note
        self.hospital = hospital
        self.examItems = examItems
        self.result = result
        self.doctorAdvice = doctorAdvice
        self.metrics = metrics
        self.answered = answered
        self.answer = answer
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
    }

    enum CodingKeys: String, CodingKey {
        case symptoms, severity, note, hospital, result, metrics
        case examItems = "exam_items"
        case doctorAdvice = "doctor_advice"
        case answered, answer, collection, done
        case category, form, ingredients, steps, verdict, reason, body, purposes
        case itemID = "item_id"
    }

    func recordData(for type: RecordType) -> RecordStructuredData {
        switch type {
        case .symptom:
            guard let symptoms, let severity else { return .unknown }
            return .symptom(SymptomRecordData(symptoms: symptoms, severity: severity, note: note))
        case .checkup:
            guard let hospital, let examItems, let result, let doctorAdvice else { return .unknown }
            return .checkup(CheckupRecordData(
                hospital: hospital, examItems: examItems, result: result,
                doctorAdvice: doctorAdvice, metrics: metrics ?? CheckupMetrics()))
        case .question:
            return .question(QuestionRecordData(answered: answered ?? false, answer: answer))
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
        case .note:
            return .note
        case .unknown:
            return .unknown
        }
    }

    init(recordData: RecordStructuredData) {
        switch recordData {
        case let .symptom(data):
            self.init(symptoms: data.symptoms, severity: data.severity, note: data.note)
        case let .checkup(data):
            self.init(
                hospital: data.hospital, examItems: data.examItems, result: data.result,
                doctorAdvice: data.doctorAdvice,
                // 没测的指标不发空对象，避免把 null 当成 0。
                metrics: data.metrics.isEmpty ? nil : data.metrics)
        case let .question(data):
            self.init(answered: data.answered, answer: data.answer)
        case let .checklist(data):
            self.init(collection: data.collection, itemID: data.itemID, done: data.done)
        case let .knowledge(data):
            self.init(
                note: data.note, category: data.category, form: data.form.rawValue,
                ingredients: data.ingredients, steps: data.steps,
                verdict: data.verdict?.rawValue, reason: data.reason, body: data.body,
                purposes: data.purposes
            )
        case .note, .unknown:
            self.init()
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

    init(draft: RecordDraft) {
        type = draft.type
        occurredAt = draft.occurredAt
        visibility = draft.visibility
        title = draft.title
        content = draft.content
        structuredData = APIRecordStructuredDataDTO(recordData: draft.structuredData)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case occurredAt = "occurred_at"
        case visibility, title, content
        case structuredData = "structured_data"
    }
}

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
