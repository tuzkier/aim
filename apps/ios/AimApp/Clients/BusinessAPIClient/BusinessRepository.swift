import Foundation

struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let detail: String?
    let status: TaskStatus
    let version: Int
    let dueAt: Date?
    let scheduledFor: Date?
    let assignedMemberID: UUID?

    var isOpen: Bool { status != .completed }
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
        case "completed": self = .completed
        case "delayed": self = .delayed
        default: self = .unknown
        }
    }
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
        TaskItem(id: dto.id, title: dto.title, detail: dto.description, status: TaskStatus(rawValue: dto.status), version: dto.version, dueAt: dto.dueAt, scheduledFor: dto.scheduledFor, assignedMemberID: dto.assignedMemberID)
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
}

extension JSONDecoder {
    static var aim: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
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
}

extension JSONEncoder {
    static var aim: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
