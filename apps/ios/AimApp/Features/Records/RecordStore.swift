import Foundation
import Observation

@MainActor
@Observable
final class RecordStore {
    var snapshot: RecordSnapshot?
    var draft: RecordDraft?
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var repository: BusinessRepositoryProtocol?

    init(repository: BusinessRepositoryProtocol? = nil) {
        self.repository = repository
    }

    func load(type: RecordType? = nil) async {
        guard let repository else { errorMessage = APIError.notConfigured.localizedDescription; return }
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await repository.fetchRecords(type: type)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ draft: RecordDraft) async -> Bool {
        guard let repository else { errorMessage = APIError.notConfigured.localizedDescription; self.draft = draft; return false }
        self.draft = draft
        isSaving = true
        defer { isSaving = false }
        do {
            let item = try await repository.createRecord(draft: draft)
            merge(item)
            self.draft = nil
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func update(recordID: UUID, draft: RecordDraft) async -> Bool {
        guard let repository else { errorMessage = APIError.notConfigured.localizedDescription; self.draft = draft; return false }
        self.draft = draft
        isSaving = true
        defer { isSaving = false }
        do {
            let item = try await repository.updateRecord(recordID: recordID, draft: draft)
            merge(item)
            self.draft = nil
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(recordID: UUID) async -> Bool {
        guard let repository else { errorMessage = APIError.notConfigured.localizedDescription; return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.deleteRecord(recordID: recordID)
            snapshot = RecordSnapshot(records: (snapshot?.records ?? []).filter { $0.id != recordID })
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createTask(from record: RecordItem, title: String, description: String?, dueAt: Date?) async -> TaskItem? {
        guard let repository else { errorMessage = APIError.notConfigured.localizedDescription; return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let task = try await repository.createTaskFromRecord(
                record: record,
                title: title,
                description: description,
                dueAt: dueAt
            )
            errorMessage = nil
            return task
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func merge(_ item: RecordItem) {
        snapshot = RecordSnapshot(records: [item] + (snapshot?.records ?? []).filter { $0.id != item.id })
    }

    static func preview() -> RecordStore {
        let now = Date.now
        let store = RecordStore()
        store.snapshot = RecordSnapshot(records: [
            RecordItem(id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(), type: .symptom, occurredAt: now.addingTimeInterval(-3_600), visibility: .family, title: nil, content: nil, structuredData: .symptom(SymptomRecordData(symptoms: ["恶心"], severity: 2, note: "早餐后明显")), attachmentRefs: [], createdAt: now.addingTimeInterval(-3_600), updatedAt: now.addingTimeInterval(-3_600)),
            RecordItem(id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(), type: .checkup, occurredAt: now.addingTimeInterval(-86_400), visibility: .family, title: nil, content: nil, structuredData: .checkup(CheckupRecordData(hospital: "杭州市妇产科医院", examItems: "常规产检", result: "正常", doctorAdvice: "按时复诊")), attachmentRefs: [], createdAt: now.addingTimeInterval(-86_400), updatedAt: now.addingTimeInterval(-86_400)),
            RecordItem(id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(), type: .note, occurredAt: now.addingTimeInterval(-172_800), visibility: .private, title: "今天的心情", content: "比上周轻松一些。", structuredData: .note, attachmentRefs: [], createdAt: now.addingTimeInterval(-172_800), updatedAt: now.addingTimeInterval(-172_800)),
        ])
        return store
    }
}
