import Foundation
import SwiftData

@Model
final class CachedTodayRecord {
    @Attribute(.unique) var pregnancyID: UUID
    var payload: Data
    var savedAt: Date

    init(pregnancyID: UUID, payload: Data, savedAt: Date = .now) {
        self.pregnancyID = pregnancyID
        self.payload = payload
        self.savedAt = savedAt
    }
}

@Model
final class EveSessionCursorRecord {
    @Attribute(.unique) var sessionID: String
    var streamIndex: Int
    var continuationToken: String?
    var updatedAt: Date

    init(sessionID: String, streamIndex: Int = 0, continuationToken: String? = nil, updatedAt: Date = .now) {
        self.sessionID = sessionID
        self.streamIndex = streamIndex
        self.continuationToken = continuationToken
        self.updatedAt = updatedAt
    }
}

@Model
final class PendingTaskOperationRecord {
    @Attribute(.unique) var idempotencyKey: String
    var taskID: UUID
    var action: String
    var payload: Data
    var createdAt: Date

    init(idempotencyKey: String, taskID: UUID, action: String, payload: Data, createdAt: Date = .now) {
        self.idempotencyKey = idempotencyKey
        self.taskID = taskID
        self.action = action
        self.payload = payload
        self.createdAt = createdAt
    }
}

enum AimModelContainerFactory {
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: CachedTodayRecord.self,
            EveSessionCursorRecord.self,
            PendingTaskOperationRecord.self,
            configurations: configuration
        )
    }
}
