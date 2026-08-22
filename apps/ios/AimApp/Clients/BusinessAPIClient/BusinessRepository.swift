import Foundation

struct TaskItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let title: String
    let detail: String?
    let status: TaskStatus
    let version: Int
    let dueAt: Date?
    let scheduledFor: Date?
    let assignedMemberID: UUID?
    let changedByActor: TaskActor

    var isOpen: Bool { status != .completed }
    var isAgentChanged: Bool { changedByActor.isAgent }
}

enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case todo
    case scheduled
    case completed
    case delayed
    case unknown

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "todo": self = .todo
        case "scheduled": self = .scheduled
        case "completed", "done": self = .completed
        case "delayed": self = .delayed
        default: self = .unknown
        }
    }
}

enum TaskActor: String, Codable, Sendable {
    case account
    case agent
    case system
    case unknown

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "account": self = .account
        case "agent": self = .agent
        case "system": self = .system
        default: self = .unknown
        }
    }

    var isAgent: Bool { self == .agent }
}

struct TodaySnapshot: Codable, Equatable, Sendable {
    let pregnancyID: UUID
    let asOf: Date
    let weeks: Int
    let days: Int
    let priorityTask: TaskItem?
    let upcomingTasks: [TaskItem]
    let familyOpenTaskCount: Int
}

struct PlanSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let pregnancyID: UUID
    let version: Int
    let tasks: [TaskItem]
}

struct FamilyMember: Identifiable, Codable, Equatable, Sendable {
    var id: UUID { accountID }
    let accountID: UUID
    let role: FamilyRole
    let status: String
    let joinedAt: Date?
}

enum FamilyRole: String, CaseIterable, Codable, Sendable {
    case mother
    case father
    case otherCaregiver = "other_caregiver"

    var displayName: String {
        switch self {
        case .mother: return "妈妈"
        case .father: return "爸爸"
        case .otherCaregiver: return "其他照护者"
        }
    }
}

struct FamilySnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let members: [FamilyMember]
}

protocol BusinessRepositoryProtocol: Sendable {
    func fetchToday() async throws -> TodaySnapshot
    func fetchPlan() async throws -> PlanSnapshot
    func fetchFamily() async throws -> FamilySnapshot
    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot
    func createPregnancy(dueDate: Date) async throws -> UUID
    func createRecord(draft: RecordDraft) async throws -> RecordItem
    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem
    func deleteRecord(recordID: UUID) async throws
    func deleteTask(taskID: UUID) async throws
    func fetchSafetyRules() async throws -> [SafetyRule]
    func fetchContentCollection(_ name: String) async throws -> ContentCollection
    func createTaskFromRecord(record: RecordItem, title: String, description: String?, dueAt: Date?) async throws -> TaskItem
    func complete(task: TaskItem) async throws -> TaskItem
    func delay(task: TaskItem, until: Date) async throws -> TaskItem
    func schedule(task: TaskItem, at: Date) async throws -> TaskItem
    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem
    func invite(phone: String, role: FamilyRole) async throws
}

actor BusinessRepository: BusinessRepositoryProtocol {
    let environment: APIEnvironment
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(environment: APIEnvironment, session: URLSession = .shared) {
        self.environment = environment
        self.session = session
        decoder = JSONDecoder.aim
        encoder = JSONEncoder.aim
    }

    func fetchToday() async throws -> TodaySnapshot {
        let pregnancyID = try requiredPregnancyID()
        let request = environment.businessRequest(path: "/api/v1/pregnancies/\(pregnancyID.uuidString)/today")
        let (data, _) = try await session.aimData(for: request)
        return map(try decoder.decode(APITodayDTO.self, from: data))
    }

    func fetchPlan() async throws -> PlanSnapshot {
        let pregnancyID = try requiredPregnancyID()
        let request = environment.businessRequest(path: "/api/v1/pregnancies/\(pregnancyID.uuidString)/plan")
        let (data, _) = try await session.aimData(for: request)
        return map(try decoder.decode(APIPlanDTO.self, from: data))
    }

    func fetchFamily() async throws -> FamilySnapshot {
        let familyID = try requiredFamilyID()
        let request = environment.businessRequest(path: "/api/v1/families/\(familyID.uuidString)")
        let (data, _) = try await session.aimData(for: request)
        return map(try decoder.decode(APIFamilyDTO.self, from: data))
    }

    func fetchRecords(type: RecordType? = nil) async throws -> RecordSnapshot {
        let pregnancyID = try requiredPregnancyID()
        let filter = type.map { "?type=\($0.rawValue)" } ?? ""
        let request = environment.businessRequest(path: "/api/v1/pregnancies/\(pregnancyID.uuidString)/records\(filter)")
        let (data, _) = try await session.aimData(for: request)
        return RecordSnapshot(records: try decoder.decode(APIRecordListDTO.self, from: data).records.map(RecordItem.init(dto:)))
    }

    func createPregnancy(dueDate: Date) async throws -> UUID {
        let familyID = try requiredFamilyID()
        let body = try encoder.encode(
            CreatePregnancyBody(dueDate: Self.dateOnlyFormatter.string(from: dueDate))
        )
        let request = environment.businessRequest(
            path: "/api/v1/families/\(familyID.uuidString)/pregnancies",
            method: "POST",
            body: body,
        )
        let (data, _) = try await session.aimData(for: request)
        let pregnancyID = try decoder.decode(CreatePregnancyResponse.self, from: data).id

        let planRequest = environment.businessRequest(
            path: "/api/v1/pregnancies/\(pregnancyID.uuidString)/plan",
            method: "POST",
            body: try encoder.encode(EmptyPlanRequest()),
        )
        _ = try await session.aimData(for: planRequest)
        return pregnancyID
    }

    func createRecord(draft: RecordDraft) async throws -> RecordItem {
        try validate(draft)
        let pregnancyID = try requiredPregnancyID()
        let request = environment.businessRequest(
            path: "/api/v1/pregnancies/\(pregnancyID.uuidString)/records",
            method: "POST",
            body: try encoder.encode(APICreateRecordDTO(draft: draft))
        )
        let (data, _) = try await session.aimData(for: request)
        return RecordItem(dto: try decoder.decode(APIRecordDTO.self, from: data))
    }

    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem {
        try validate(draft)
        let pregnancyID = try requiredPregnancyID()
        let request = environment.businessRequest(
            path: "/api/v1/pregnancies/\(pregnancyID.uuidString)/records/\(recordID.uuidString)",
            method: "PATCH",
            body: try encoder.encode(APIUpdateRecordDTO(draft: draft))
        )
        let (data, _) = try await session.aimData(for: request)
        return RecordItem(dto: try decoder.decode(APIRecordDTO.self, from: data))
    }

    func deleteRecord(recordID: UUID) async throws {
        let pregnancyID = try requiredPregnancyID()
        let request = environment.businessRequest(
            path: "/api/v1/pregnancies/\(pregnancyID.uuidString)/records/\(recordID.uuidString)",
            method: "DELETE"
        )
        _ = try await session.aimData(for: request)
    }

    /// 危险信号是静态安全内容，不含个人数据，后端也不要求登录。
    func fetchSafetyRules() async throws -> [SafetyRule] {
        let request = environment.businessRequest(path: "/api/v1/safety-rules")
        let (data, _) = try await session.aimData(for: request)
        return try decoder.decode(APISafetyRuleListDTO.self, from: data).items.map(SafetyRule.init(dto:))
    }

    /// 可浏览的内容集合（办事指南、待产准备）。集合名由服务端白名单校验。
    func fetchContentCollection(_ name: String) async throws -> ContentCollection {
        let request = environment.businessRequest(path: "/api/v1/content/\(name)")
        let (data, _) = try await session.aimData(for: request)
        return ContentCollection(dto: try decoder.decode(APIContentCollectionDTO.self, from: data))
    }

    /// 硬删除任务。用于撤销「Agent 新建的待办」——undo_operation 做的是字段级还原，
    /// 新建没有可还原的前值。
    func deleteTask(taskID: UUID) async throws {
        let pregnancyID = try requiredPregnancyID()
        let request = environment.businessRequest(
            path: "/api/v1/pregnancies/\(pregnancyID.uuidString)/tasks/\(taskID.uuidString)",
            method: "DELETE"
        )
        _ = try await session.aimData(for: request)
    }

    func createTaskFromRecord(record: RecordItem, title: String, description: String?, dueAt: Date?) async throws -> TaskItem {
        let pregnancyID = try requiredPregnancyID()
        guard record.pregnancyID == pregnancyID else { throw APIError.invalidResponse }
        let request = environment.businessRequest(
            path: "/api/v1/pregnancies/\(pregnancyID.uuidString)/tasks",
            method: "POST",
            body: try encoder.encode(CreateTaskFromRecordBody(title: title, description: description, dueAt: dueAt, recordID: record.id))
        )
        let (data, _) = try await session.aimData(for: request)
        return map(try decoder.decode(APITaskDTO.self, from: data))
    }

    func complete(task: TaskItem) async throws -> TaskItem {
        try await mutate(path: "/api/v1/tasks/\(task.id.uuidString)/complete", body: APIExpectedVersionDTO(expectedVersion: task.version))
    }

    func delay(task: TaskItem, until: Date) async throws -> TaskItem {
        try await mutate(path: "/api/v1/tasks/\(task.id.uuidString)/delay", body: APIDelayTaskDTO(expectedVersion: task.version, dueAt: until))
    }

    func schedule(task: TaskItem, at: Date) async throws -> TaskItem {
        try await mutate(path: "/api/v1/tasks/\(task.id.uuidString)/schedule", body: APIScheduleTaskDTO(expectedVersion: task.version, scheduledFor: at))
    }

    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem {
        try await mutate(path: "/api/v1/tasks/\(task.id.uuidString)/assign", body: APIAssignTaskDTO(expectedVersion: task.version, assignedMemberID: memberID))
    }

    func invite(phone: String, role: FamilyRole) async throws {
        let familyID = try requiredFamilyID()
        struct Body: Encodable { let inviteePhone: String; let role: String; enum CodingKeys: String, CodingKey { case inviteePhone = "invitee_phone"; case role } }
        let body = try encoder.encode(Body(inviteePhone: phone, role: role.rawValue))
        let request = environment.businessRequest(path: "/api/v1/families/\(familyID.uuidString)/invitations", method: "POST", body: body)
        _ = try await session.aimData(for: request)
    }

    private func mutate<Body: Encodable>(path: String, body: Body) async throws -> TaskItem {
        let data = try encoder.encode(body)
        let request = environment.businessRequest(path: path, method: "POST", body: data)
        let (responseData, _) = try await session.aimData(for: request)
        return map(try decoder.decode(APITaskDTO.self, from: responseData))
    }

    private func requiredPregnancyID() throws -> UUID {
        guard let id = environment.pregnancyID else { throw APIError.notConfigured }
        return id
    }

    private func requiredFamilyID() throws -> UUID {
        guard let id = environment.familyID else { throw APIError.notConfigured }
        return id
    }

    private func map(_ dto: APITaskDTO) -> TaskItem {
        TaskItem(
            id: dto.id,
            title: dto.title,
            detail: dto.description,
            status: TaskStatus(rawValue: dto.status),
            version: dto.version,
            dueAt: dto.dueAt,
            scheduledFor: dto.scheduledFor,
            assignedMemberID: dto.assignedMemberID,
            changedByActor: TaskActor(rawValue: dto.changedByActorType)
        )
    }

    private func map(_ dto: APITodayDTO) -> TodaySnapshot {
        TodaySnapshot(pregnancyID: dto.pregnancyID, asOf: dto.asOf, weeks: dto.gestationalAge.weeks, days: dto.gestationalAge.days, priorityTask: dto.priorityTask.map(map), upcomingTasks: dto.upcomingTasks.map(map), familyOpenTaskCount: dto.familyTaskCounts.reduce(0) { $0 + $1.openCount })
    }

    private func map(_ dto: APIPlanDTO) -> PlanSnapshot {
        PlanSnapshot(id: dto.id, pregnancyID: dto.pregnancyID, version: dto.version, tasks: dto.tasks.map(map))
    }

    private func map(_ dto: APIFamilyDTO) -> FamilySnapshot {
        FamilySnapshot(id: dto.id, name: dto.name, members: dto.members.map { member in
            FamilyMember(accountID: member.accountID, role: FamilyRole(rawValue: member.role) ?? .otherCaregiver, status: member.status, joinedAt: member.joinedAt)
        })
    }

    private func validate(_ draft: RecordDraft) throws {
        guard draft.visibility != .unknown else { throw APIError.invalidResponse }
        switch (draft.type, draft.structuredData) {
        case (.symptom, .symptom), (.checkup, .checkup), (.note, .note),
             (.question, .question), (.checklist, .checklist):
            return
        default:
            throw APIError.invalidResponse
        }
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct CreatePregnancyBody: Encodable {
    let dueDate: String

    enum CodingKeys: String, CodingKey {
        case dueDate = "due_date"
    }
}

private struct CreatePregnancyResponse: Decodable {
    let id: UUID
}

private struct EmptyPlanRequest: Encodable {
    let asOf: String? = nil

    enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
    }
}

private struct CreateTaskFromRecordBody: Encodable {
    let title: String
    let description: String?
    let dueAt: Date?
    let recordID: UUID
    let sourceType = "record"

    enum CodingKeys: String, CodingKey {
        case title, description
        case dueAt = "due_at"
        case recordID = "record_id"
        case sourceType = "source_type"
    }
}

extension JSONDecoder {
    static var aim: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = fractionalISO8601Formatter.date(from: value) { return date }
            if let date = ISO8601DateFormatter().date(from: value) { return date }
            let dateOnly = DateFormatter()
            dateOnly.calendar = Calendar(identifier: .gregorian)
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.dateFormat = "yyyy-MM-dd"
            if let date = dateOnly.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported Aim date: \(value)")
        }
        return decoder
    }

    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension JSONEncoder {
    static var aim: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
