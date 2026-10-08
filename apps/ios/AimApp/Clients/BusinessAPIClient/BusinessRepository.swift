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
    /// 家里怎么称呼这个人。为空时回退到角色名——两个「其他家人」
    /// 只显示角色的话，在列表里完全分不出谁是谁。
    let nickname: String?
    let status: String
    let joinedAt: Date?
    /// 管理员 = 家庭创建人，只有他能移出别人。
    var isAdmin = false

    var displayName: String {
        guard let nickname, !nickname.trimmingCharacters(in: .whitespaces).isEmpty else {
            return role.displayName
        }
        return nickname
    }
}

enum FamilyRole: String, CaseIterable, Codable, Sendable {
    case mother
    case father
    case otherCaregiver = "other_caregiver"

    var displayName: String {
        switch self {
        case .mother: return "妈妈"
        case .father: return "爸爸"
        // 「其他照护者」是书面语，注册页上直接给用户看太生硬。
        case .otherCaregiver: return "其他家人"
        }
    }
}

struct FamilySnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let members: [FamilyMember]
    /// 还没处理完的邀请（含过期 7 天内的，方便重发）。
    var invitations: [FamilyInvitation] = []

    var admin: FamilyMember? { members.first(where: \.isAdmin) }
}

/// 家里发出去、还没被接受的邀请。
struct FamilyInvitation: Identifiable, Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending, declined, expired
    }

    let id: UUID
    /// 打码后的手机号，如 138****5678。
    let phoneMasked: String
    let role: FamilyRole
    let invitedBy: UUID
    let expiresAt: Date
    let status: Status

    var isExpired: Bool { status == .expired }
}

/// 发给我的邀请。
struct MyInvitation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let familyID: UUID
    let familyName: String
    let inviterName: String
    let role: FamilyRole
    let expiresAt: Date
    /// pending 或 declined（点过「暂不」）。
    let status: String
    let canAccept: Bool
    let blockedReason: String?

    var wasDeclined: Bool { status == "declined" }
}

/// 当前账号所在的家庭与孕期。接受邀请、退出、被移出后据此切换会话。
struct MeSnapshot: Codable, Equatable, Sendable {
    let familyID: UUID
    let pregnancyID: UUID?
}

struct PregnancySummary: Codable, Equatable, Sendable {
    let id: UUID
    let dueDate: Date
    let weeks: Int
    let days: Int
}

struct MemberDetail: Equatable, Sendable {
    let member: FamilyMember
    let openTasks: [TaskItem]
    let recentRecords: [RecordItem]
}

struct FamilyActivityItem: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case taskCreated = "task_created"
        case taskCompleted = "task_completed"
        case recordCreated = "record_created"
        case memberJoined = "member_joined"
        case memberLeft = "member_left"
        case memberRemoved = "member_removed"
        case dueDateChanged = "due_date_changed"
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    let id: String
    let kind: Kind
    let actorName: String
    let title: String
    let targetType: String?
    let targetID: UUID?
    let targetDeleted: Bool
    let viaAgent: Bool
    let createdAt: Date

    /// 动态里的一句话，如「老王 完成了「买产褥垫」」。
    var sentence: String {
        switch kind {
        case .taskCreated: "\(actorName)\(viaAgent ? " 通过 AIM" : "") 新建了「\(title)」"
        case .taskCompleted: "\(actorName) 完成了「\(title)」"
        case .recordCreated: "\(actorName) 记了「\(title)」"
        case .memberJoined: "\(actorName) 加入了家庭"
        case .memberLeft: "\(actorName) 退出了家庭"
        case .memberRemoved: "\(actorName) 把 \(title) 移出了家庭"
        case .dueDateChanged: "\(actorName) 把预产期改为 \(title)"
        case .unknown: "\(actorName) 有一条新动态"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case actorName = "actor_name"
        case targetType = "target_type"
        case targetID = "target_id"
        case targetDeleted = "target_deleted"
        case viaAgent = "via_agent"
        case createdAt = "created_at"
    }
}

struct FamilyActivityPage: Equatable, Sendable {
    let items: [FamilyActivityItem]
    /// 下一页的起点，原样传回服务端（保留微秒，不经 Date 转换以免丢精度）；没有更早的了就是 nil。
    let nextBefore: String?
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
    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem
    func complete(task: TaskItem) async throws -> TaskItem
    func delay(task: TaskItem, until: Date) async throws -> TaskItem
    func schedule(task: TaskItem, at: Date) async throws -> TaskItem
    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem
    func invite(phone: String, role: FamilyRole) async throws
    func renameFamily(to name: String) async throws
    func updateMyMembership(nickname: String?, role: FamilyRole?) async throws
    func requestAccountDeletion(password: String) async throws
    func fetchPregnancy() async throws -> PregnancySummary?
    func updateDueDate(_ dueDate: Date) async throws -> PregnancySummary
    func fetchMemberDetail(accountID: UUID) async throws -> MemberDetail
    func fetchActivity(before: String?) async throws -> FamilyActivityPage
    func revokeInvitation(id: UUID) async throws
    func fetchMyInvitations() async throws -> [MyInvitation]
    func acceptInvitation(id: UUID) async throws -> MeSnapshot
    func declineInvitation(id: UUID) async throws
    func leaveFamily() async throws -> MeSnapshot
    func removeMember(accountID: UUID) async throws
    func fetchMe() async throws -> MeSnapshot
    func fetchWeeklyContent() async throws -> WeeklyContentBook
}

/// 新加的家庭接口给出默认实现：只关心别的接口的测试替身不必逐个补齐。
extension BusinessRepositoryProtocol {
    func fetchPregnancy() async throws -> PregnancySummary? { throw APIError.notConfigured }
    func updateDueDate(_ dueDate: Date) async throws -> PregnancySummary { throw APIError.notConfigured }
    func fetchMemberDetail(accountID: UUID) async throws -> MemberDetail { throw APIError.notConfigured }
    func fetchActivity(before: String?) async throws -> FamilyActivityPage { throw APIError.notConfigured }
    func revokeInvitation(id: UUID) async throws { throw APIError.notConfigured }
    func fetchMyInvitations() async throws -> [MyInvitation] { throw APIError.notConfigured }
    func acceptInvitation(id: UUID) async throws -> MeSnapshot { throw APIError.notConfigured }
    func declineInvitation(id: UUID) async throws { throw APIError.notConfigured }
    func leaveFamily() async throws -> MeSnapshot { throw APIError.notConfigured }
    func removeMember(accountID: UUID) async throws { throw APIError.notConfigured }
    func fetchMe() async throws -> MeSnapshot { throw APIError.notConfigured }
    func fetchWeeklyContent() async throws -> WeeklyContentBook { throw APIError.notConfigured }
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
        return try await postTask(CreateTaskBody(
            title: title, description: description, dueAt: dueAt,
            assignedMemberID: nil, recordID: record.id, sourceType: "record"))
    }

    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem {
        try await postTask(CreateTaskBody(
            title: title, description: description, dueAt: dueAt,
            assignedMemberID: assignedMemberID, recordID: nil, sourceType: nil))
    }

    private func postTask(_ body: CreateTaskBody) async throws -> TaskItem {
        let pregnancyID = try requiredPregnancyID()
        let request = environment.businessRequest(
            path: "/api/v1/pregnancies/\(pregnancyID.uuidString)/tasks",
            method: "POST",
            body: try encoder.encode(body)
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

    func renameFamily(to name: String) async throws {
        let familyID = try requiredFamilyID()
        struct Body: Encodable { let name: String }
        let body = try encoder.encode(Body(name: name))
        let request = environment.businessRequest(
            path: "/api/v1/families/\(familyID.uuidString)", method: "PATCH", body: body)
        _ = try await session.aimData(for: request)
    }

    /// 只改自己。端点里没有 member_id——改别人需要一套「谁能改谁」的权限模型。
    func updateMyMembership(nickname: String?, role: FamilyRole?) async throws {
        let familyID = try requiredFamilyID()
        // nil 表示「这次不改这一项」，不是「清空」。两者混同的话，
        // 只想改称呼的请求会把角色抹掉。
        struct Body: Encodable { let nickname: String?; let role: String? }
        let body = try encoder.encode(Body(nickname: nickname, role: role?.rawValue))
        let request = environment.businessRequest(
            path: "/api/v1/families/\(familyID.uuidString)/members/me", method: "PATCH", body: body)
        _ = try await session.aimData(for: request)
    }

    /// 申请注销。服务端进入 30 天缓冲期，旧票立即失效，所以调用方成功后要 `session.clear()`。
    func requestAccountDeletion(password: String) async throws {
        struct Body: Encodable { let password: String }
        let request = environment.businessRequest(
            path: "/api/v1/auth/deletion-request", method: "POST",
            body: try encoder.encode(Body(password: password)))
        // 这个端点的 401 是「密码不对」，得留在表单里给用户看；若按票作废处理，
        // 会话会被清掉、表单直接消失。票真过期了也只是多显示一次「密码不对」，
        // 下一个普通请求会照常触发会话过期。
        _ = try await session.aimData(for: request, broadcastsUnauthorized: false)
    }

    // MARK: 个人资料与家庭

    func fetchPregnancy() async throws -> PregnancySummary? {
        guard let pregnancyID = environment.pregnancyID else { return nil }
        let request = environment.businessRequest(path: "/api/v1/pregnancies/\(pregnancyID.uuidString)")
        let (data, _) = try await session.aimData(for: request)
        return try decoder.decode(PregnancyDTO.self, from: data).summary
    }

    func updateDueDate(_ dueDate: Date) async throws -> PregnancySummary {
        let pregnancyID = try requiredPregnancyID()
        let body = try encoder.encode(CreatePregnancyBody(dueDate: Self.dateOnlyFormatter.string(from: dueDate)))
        let request = environment.businessRequest(
            path: "/api/v1/pregnancies/\(pregnancyID.uuidString)", method: "PATCH", body: body)
        let (data, _) = try await session.aimData(for: request)
        return try decoder.decode(PregnancyDTO.self, from: data).summary
    }

    func fetchMemberDetail(accountID: UUID) async throws -> MemberDetail {
        let familyID = try requiredFamilyID()
        let request = environment.businessRequest(
            path: "/api/v1/families/\(familyID.uuidString)/members/\(accountID.uuidString)")
        let (data, _) = try await session.aimData(for: request)
        let dto = try decoder.decode(MemberDetailDTO.self, from: data)
        return MemberDetail(
            member: map(dto.member),
            openTasks: dto.openTasks.map(map),
            recentRecords: dto.recentRecords.map(RecordItem.init(dto:)))
    }

    func fetchActivity(before: String?) async throws -> FamilyActivityPage {
        let familyID = try requiredFamilyID()
        var path = "/api/v1/families/\(familyID.uuidString)/activity"
        if let before {
            path += "?before=\(before.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? before)"
        }
        let (data, _) = try await session.aimData(for: environment.businessRequest(path: path))
        let dto = try decoder.decode(ActivityPageDTO.self, from: data)
        return FamilyActivityPage(items: dto.items, nextBefore: dto.nextBefore)
    }

    func revokeInvitation(id: UUID) async throws {
        let familyID = try requiredFamilyID()
        let request = environment.businessRequest(
            path: "/api/v1/families/\(familyID.uuidString)/invitations/\(id.uuidString)", method: "DELETE")
        _ = try await session.aimData(for: request)
    }

    func fetchMyInvitations() async throws -> [MyInvitation] {
        let (data, _) = try await session.aimData(for: environment.businessRequest(path: "/api/v1/me/invitations"))
        return try decoder.decode(MyInvitationsDTO.self, from: data).invitations.map(\.model)
    }

    func acceptInvitation(id: UUID) async throws -> MeSnapshot {
        let request = environment.businessRequest(
            path: "/api/v1/me/invitations/\(id.uuidString)/accept", method: "POST")
        let (data, _) = try await session.aimData(for: request)
        return try decoder.decode(MeDTO.self, from: data).snapshot
    }

    func declineInvitation(id: UUID) async throws {
        let request = environment.businessRequest(
            path: "/api/v1/me/invitations/\(id.uuidString)/decline", method: "POST")
        _ = try await session.aimData(for: request)
    }

    func leaveFamily() async throws -> MeSnapshot {
        let familyID = try requiredFamilyID()
        let request = environment.businessRequest(
            path: "/api/v1/families/\(familyID.uuidString)/members/me/leave", method: "POST")
        let (data, _) = try await session.aimData(for: request)
        return try decoder.decode(MeDTO.self, from: data).snapshot
    }

    func removeMember(accountID: UUID) async throws {
        let familyID = try requiredFamilyID()
        let request = environment.businessRequest(
            path: "/api/v1/families/\(familyID.uuidString)/members/\(accountID.uuidString)", method: "DELETE")
        _ = try await session.aimData(for: request)
    }

    func fetchMe() async throws -> MeSnapshot {
        let (data, _) = try await session.aimData(for: environment.businessRequest(path: "/api/v1/me"))
        return try decoder.decode(MeDTO.self, from: data).snapshot
    }

    func fetchWeeklyContent() async throws -> WeeklyContentBook {
        let (data, _) = try await session.aimData(for: environment.businessRequest(path: "/api/v1/content/weekly"))
        return try JSONDecoder().decode(WeeklyContentBook.self, from: data)
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
        FamilySnapshot(
            id: dto.id,
            name: dto.name,
            members: dto.members.map(map),
            invitations: (dto.invitations ?? []).map { invitation in
                FamilyInvitation(
                    id: invitation.id,
                    phoneMasked: invitation.phoneMasked,
                    role: FamilyRole(rawValue: invitation.role) ?? .otherCaregiver,
                    invitedBy: invitation.invitedBy,
                    expiresAt: invitation.expiresAt,
                    status: FamilyInvitation.Status(rawValue: invitation.status) ?? .pending)
            })
    }

    private func map(_ member: APIFamilyMemberDTO) -> FamilyMember {
        FamilyMember(
            accountID: member.accountID,
            role: FamilyRole(rawValue: member.role) ?? .otherCaregiver,
            nickname: member.nickname,
            status: member.status,
            joinedAt: member.joinedAt,
            isAdmin: member.isAdmin ?? false)
    }

    private func validate(_ draft: RecordDraft) throws {
        guard draft.visibility != .unknown else { throw APIError.invalidResponse }
        switch (draft.type, draft.structuredData) {
        // 每加一种记录类型都要记得补这里，否则请求发不出去而后端明明支持。
        // KnowledgeComposer / RecordComposer 已经各自校验过内容，这里只确认
        // 类型与结构化数据是配套的。
        case (.symptom, .symptom), (.checkup, .checkup), (.note, .note),
             (.question, .question), (.checklist, .checklist),
             (.knowledge, .knowledge):
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

struct CreateTaskBody: Encodable {
    let title: String
    let description: String?
    let dueAt: Date?
    let assignedMemberID: UUID?
    let recordID: UUID?
    /// nil 时不发这个字段，服务端默认 `user`。
    let sourceType: String?

    enum CodingKeys: String, CodingKey {
        case title, description
        case dueAt = "due_at"
        case assignedMemberID = "assigned_member_id"
        case recordID = "record_id"
        case sourceType = "source_type"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(dueAt, forKey: .dueAt)
        try container.encodeIfPresent(assignedMemberID, forKey: .assignedMemberID)
        try container.encodeIfPresent(recordID, forKey: .recordID)
        try container.encodeIfPresent(sourceType, forKey: .sourceType)
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


// MARK: - 个人资料与家庭接口的返回结构

private struct PregnancyDTO: Decodable {
    struct Age: Decodable { let weeks: Int; let days: Int }
    let id: UUID
    let dueDate: Date
    let gestationalAge: Age

    enum CodingKeys: String, CodingKey {
        case id
        case dueDate = "due_date"
        case gestationalAge = "gestational_age"
    }

    var summary: PregnancySummary {
        PregnancySummary(id: id, dueDate: dueDate, weeks: gestationalAge.weeks, days: gestationalAge.days)
    }
}

private struct MemberDetailDTO: Decodable {
    let member: APIFamilyMemberDTO
    let openTasks: [APITaskDTO]
    let recentRecords: [APIRecordDTO]

    enum CodingKeys: String, CodingKey {
        case member
        case openTasks = "open_tasks"
        case recentRecords = "recent_records"
    }
}

private struct ActivityPageDTO: Decodable {
    let items: [FamilyActivityItem]
    let nextBefore: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextBefore = "next_before"
    }
}

private struct MyInvitationsDTO: Decodable {
    struct Item: Decodable {
        let id: UUID
        let familyID: UUID
        let familyName: String
        let inviterName: String
        let role: String
        let expiresAt: Date
        let status: String
        let canAccept: Bool
        let blockedReason: String?

        enum CodingKeys: String, CodingKey {
            case id, role, status
            case familyID = "family_id"
            case familyName = "family_name"
            case inviterName = "inviter_name"
            case expiresAt = "expires_at"
            case canAccept = "can_accept"
            case blockedReason = "blocked_reason"
        }

        var model: MyInvitation {
            MyInvitation(
                id: id, familyID: familyID, familyName: familyName, inviterName: inviterName,
                role: FamilyRole(rawValue: role) ?? .otherCaregiver, expiresAt: expiresAt,
                status: status, canAccept: canAccept, blockedReason: blockedReason)
        }
    }

    let invitations: [Item]
}

private struct MeDTO: Decodable {
    let familyID: UUID
    let pregnancyID: UUID?

    enum CodingKeys: String, CodingKey {
        case familyID = "family_id"
        case pregnancyID = "pregnancy_id"
    }

    var snapshot: MeSnapshot { MeSnapshot(familyID: familyID, pregnancyID: pregnancyID) }
}
