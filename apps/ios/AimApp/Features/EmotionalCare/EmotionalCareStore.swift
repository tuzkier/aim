import Foundation
import Observation

@MainActor
@Observable
final class EmotionalCareStore {
    let repository: BusinessRepositoryProtocol?
    let accountID: UUID
    private(set) var records: [RecordItem] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    var error: String?
    private var generation = 0

    init(repository: BusinessRepositoryProtocol?, accountID: UUID) {
        self.repository = repository
        self.accountID = accountID
    }

    func todayMood(now: Date = .now) -> RecordItem? {
        records.first {
            $0.type == .mood && $0.authorAccountID == accountID &&
            EmotionalSchedule.calendar.isDate($0.occurredAt, inSameDayAs: now)
        }
    }

    func load() async {
        guard let repository else { return }
        generation += 1
        let requestedGeneration = generation
        isLoading = true
        defer { if generation == requestedGeneration { isLoading = false } }
        do {
            async let moods = repository.fetchRecords(type: .mood)
            async let assessments = repository.fetchRecords(type: .epds)
            let (moodSnapshot, assessmentSnapshot) = try await (moods, assessments)
            let values = moodSnapshot.records + assessmentSnapshot.records
            guard generation == requestedGeneration else { return }
            records = values.filter { $0.authorAccountID == accountID }.sorted { $0.occurredAt > $1.occurredAt }
            error = nil
        } catch {
            if generation == requestedGeneration { self.error = error.localizedDescription }
        }
    }

    @discardableResult
    func save(_ draft: RecordDraft, editing record: RecordItem? = nil) async -> Bool {
        guard !isSaving, record == nil || record?.authorAccountID == accountID else { return false }
        guard let repository else { error = APIError.notConfigured.localizedDescription; return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved: RecordItem
            if let record { saved = try await repository.updateRecord(recordID: record.id, draft: draft) }
            else { saved = try await repository.createRecord(draft: draft) }
            generation += 1
            isLoading = false
            records.removeAll { $0.id == saved.id }
            records.append(saved)
            records.sort { $0.occurredAt > $1.occurredAt }
            error = nil
            NotificationCenter.default.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["record"]])
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func delete(_ record: RecordItem) async -> Bool {
        guard record.authorAccountID == accountID, !isSaving, let repository else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.deleteRecord(recordID: record.id)
            generation += 1
            isLoading = false
            records.removeAll { $0.id == record.id }
            NotificationCenter.default.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["record"]])
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
