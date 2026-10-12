import Foundation
import Observation

@MainActor
@Observable
final class PostpartumStore {
    let repository: BusinessRepositoryProtocol?
    var pregnancy: PregnancySummary?
    var babies: [BabyProfile] = []
    var selectedBabyID: UUID?
    var records: [RecordItem] = []
    var tasks: [TaskItem] = []
    let content = PostpartumContent.load()
    private(set) var isLoading = false
    private(set) var isSaving = false
    var error: String?
    private var generation = 0
    var selectedBaby: BabyProfile? { babies.first { $0.id == selectedBabyID } ?? babies.first }
    var visibleRecords: [RecordItem] {
        guard let selectedBaby else { return [] }
        return records.filter { $0.babyCare?.babyID == selectedBaby.id }.sorted { $0.occurredAt > $1.occurredAt }
    }
    var currentSchedule: [TaskItem] {
        guard let revision = pregnancy?.birthRevision else { return [] }
        let prefix = "postpartum.\(revision.uuidString.lowercased())."
        return tasks.filter { ($0.sourceID ?? "").hasPrefix(prefix) }.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    init(repository: BusinessRepositoryProtocol?, pregnancy: PregnancySummary? = nil) {
        self.repository = repository; self.pregnancy = pregnancy
    }

    func load() async {
        guard let repository else { error = APIError.notConfigured.localizedDescription; return }
        generation += 1
        let request = generation
        isLoading = true
        defer { if request == generation { isLoading = false } }
        do {
            async let p = repository.fetchPregnancy()
            async let b = repository.fetchBabies()
            async let planRequest = repository.fetchPlan()
            async let feeds = repository.fetchRecords(type: .feeding)
            async let diapers = repository.fetchRecords(type: .diaper)
            async let sleeps = repository.fetchRecords(type: .sleep)
            let (pregnancy, babies, plan, feeding, diaper, sleep) = try await (p, b, planRequest, feeds, diapers, sleeps)
            guard request == generation else { return }
            self.pregnancy = pregnancy
            self.babies = babies
            self.tasks = plan.tasks
            self.records = feeding.records + diaper.records + sleep.records
            if !babies.contains(where: { $0.id == selectedBabyID }) { selectedBabyID = babies.first?.id }
            error = nil
        } catch { if request == generation { self.error = error.localizedDescription } }
    }

    func recordBirth(date: Date, babies: [BabyDraft]) async -> Bool {
        await mutate {
            let value = try await self.repository!.recordBirth(date: date, babies: babies)
            self.pregnancy = value.pregnancy; self.babies = value.babies
            self.selectedBabyID = value.babies.first?.id
        }
    }
    func correctBirth(_ date: Date) async -> Bool {
        await mutate {
            let value = try await self.repository!.updateBirthDate(date)
            self.pregnancy = value.pregnancy; self.babies = value.babies
        }
    }
    func retractBirth() async -> Bool {
        await mutate {
            self.pregnancy = try await self.repository!.retractBirth()
            self.babies = []; self.selectedBabyID = nil
        }
    }
    func saveBaby(_ draft: BabyDraft, existingID: UUID?) async -> Bool {
        await mutate {
            let value = try await self.repository!.saveBaby(draft, id: existingID)
            self.babies.removeAll { $0.id == value.id }; self.babies.append(value)
            self.selectedBabyID = value.id
        }
    }
    func saveCare(_ draft: RecordDraft, existingID: UUID?) async -> Bool {
        await mutate {
            let value: RecordItem
            if let existingID { value = try await self.repository!.updateRecord(recordID: existingID, draft: draft) }
            else { value = try await self.repository!.createRecord(draft: draft) }
            self.records.removeAll { $0.id == value.id }; self.records.append(value)
        }
    }
    func deleteCare(_ record: RecordItem) async -> Bool {
        await mutate {
            try await self.repository!.deleteRecord(recordID: record.id)
            self.records.removeAll { $0.id == record.id }
        }
    }
    func complete(_ task: TaskItem) async -> Bool {
        await mutate {
            let value = try await self.repository!.complete(task: task)
            self.tasks.removeAll { $0.id == value.id }; self.tasks.append(value)
        }
    }

    private func mutate(_ operation: () async throws -> Void) async -> Bool {
        guard !isSaving else { return false }
        guard repository != nil else { error = APIError.notConfigured.localizedDescription; return false }
        isSaving = true
        generation += 1; isLoading = false
        defer { isSaving = false }
        do {
            try await operation()
            generation += 1
            error = nil
            NotificationCenter.default.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["pregnancy", "record", "task"]])
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
