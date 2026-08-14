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
    let status: String
    let invitedAt: Date?
    let joinedAt: Date?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case role, status
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
