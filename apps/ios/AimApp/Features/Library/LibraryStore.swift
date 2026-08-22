import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    var repository: BusinessRepositoryProtocol?
    var snapshot = LibrarySnapshot()
    var safetyRules: [SafetyRule] = []
    var collections: [String: ContentCollection] = [:]
    var isLoading = false
    var errorMessage: String?

    func load() async {
        guard let repository else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // 危险信号是静态内容，记录是个人数据；两者失败原因不同，
            // 但对用户来说资料库要么打开要么没打开，所以一起取。
            async let records = repository.fetchRecords(type: nil)
            async let rules = repository.fetchSafetyRules()
            async let paperwork = repository.fetchContentCollection("hangzhou")
            async let preparation = repository.fetchContentCollection("preparation")
            async let nutrition = repository.fetchContentCollection("nutrition")
            let loaded = try await (records, rules, paperwork, preparation, nutrition)
            safetyRules = loaded.1
            collections = [
                "hangzhou": loaded.2, "preparation": loaded.3, "nutrition": loaded.4,
            ]
            snapshot = LibrarySnapshot(
                records: loaded.0.records,
                safetyRuleCount: loaded.1.count,
                collectionSizes: collections.mapValues(\.items.count)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 写入

    func addQuestion(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let repository else { return }
        let draft = RecordDraft(
            type: .question,
            occurredAt: .now,
            visibility: .family,
            title: nil,
            content: trimmed,
            structuredData: .question(QuestionRecordData(answered: false, answer: nil))
        )
        await perform { _ = try await repository.createRecord(draft: draft) }
    }

    func markQuestionAnswered(_ record: RecordItem, answer: String?) async {
        guard let repository else { return }
        let trimmed = answer?.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = RecordDraft(
            type: .question,
            occurredAt: record.occurredAt,
            visibility: record.visibility,
            title: record.title,
            content: record.content,
            structuredData: .question(
                QuestionRecordData(answered: true, answer: trimmed?.isEmpty == true ? nil : trimmed)
            )
        )
        await perform { _ = try await repository.updateRecord(recordID: record.id, draft: draft) }
    }

    /// 勾选 / 取消勾选一个清单条目。
    ///
    /// 已有记录就更新，没有才新建——否则同一个条目会攒出一堆记录，
    /// 进度算出来永远是错的。
    func toggleChecklistItem(collection: String, itemID: String) async {
        guard let repository else { return }
        let existing = checklistRecord(collection: collection, itemID: itemID)
        let nextDone = !(existing.map(isDone) ?? false)
        let draft = RecordDraft(
            type: .checklist,
            occurredAt: existing?.occurredAt ?? .now,
            visibility: .family,
            title: nil,
            content: nil,
            structuredData: .checklist(
                ChecklistRecordData(collection: collection, itemID: itemID, done: nextDone)
            )
        )
        await perform {
            if let existing {
                _ = try await repository.updateRecord(recordID: existing.id, draft: draft)
            } else {
                _ = try await repository.createRecord(draft: draft)
            }
        }
    }

    func isChecked(collection: String, itemID: String) -> Bool {
        checklistRecord(collection: collection, itemID: itemID).map(isDone) ?? false
    }

    private func checklistRecord(collection: String, itemID: String) -> RecordItem? {
        snapshot.records.first { record in
            guard case let .checklist(data) = record.structuredData else { return false }
            // 集合名一并比对——不同集合的同名条目是两回事。
            return data.collection == collection && data.itemID == itemID
        }
    }

    private func isDone(_ record: RecordItem) -> Bool {
        guard case let .checklist(data) = record.structuredData else { return false }
        return data.done
    }

    private func perform(_ work: () async throws -> Void) async {
        do {
            try await work()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func records(in category: LibraryCategoryID) -> [RecordItem] {
        switch category {
        case .symptoms: snapshot.records.filter { $0.type == .symptom }
            .sorted { $0.occurredAt > $1.occurredAt }
        case .checkups: snapshot.records.filter { $0.type == .checkup }
            .sorted { $0.occurredAt > $1.occurredAt }
        default: []
        }
    }
}
