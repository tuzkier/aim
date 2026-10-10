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
    var encyclopedia = EncyclopediaCatalog()
    /// 当前孕周。「这周读什么」与主题页的「本周」标记靠它；取不到时这两处不显示。
    var currentWeek: Int?
    private var entryCache: [String: EncyclopediaEntry] = [:]

    func load() async {
        // 重入保护取代了原来的「只加载一次」判断——后者会让资料库
        // 永远停在首次快照上，用户在时间线新记的产检这里看不到。
        guard let repository, !isLoading else { return }
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
            // 百科与孕周取不到不该让整个资料库打不开：它们缺席时对应区块不显示即可。
            async let catalog = try? repository.fetchEncyclopediaCatalog()
            async let pregnancy = try? repository.fetchPregnancy()
            // 生产不加载草稿百科时，「吃什么」回退到已审核的 nutrition 集合；它同样单独容错。
            async let nutrition = try? repository.fetchContentCollection("nutrition")
            let loaded = try await (records, rules, paperwork, preparation)
            safetyRules = loaded.1
            collections = ["hangzhou": loaded.2, "preparation": loaded.3]
            if let fetched = await nutrition { collections["nutrition"] = fetched }
            // 记录列表和时间线要靠它把 item_id 换回标题。
            ContentTitleIndex.register(collections)
            if let fetched = await catalog { encyclopedia = fetched }
            if let fetched = await pregnancy { currentWeek = fetched.weeks }
            snapshot = LibrarySnapshot(
                records: loaded.0.records,
                // 通栏条数要和自查页实际显示的一致：按当前孕周过滤后再数。
                safetyRuleCount: SafetyCheck.rules(loaded.1, forWeek: currentWeek).count,
                collectionSizes: collections.mapValues(\.items.count),
                // 主题编号重复时取第一个——服务端数据出错不该让资料库闪退。
                encyclopediaCounts: Dictionary(
                    encyclopedia.topics.map { ($0.id, $0.count) },
                    uniquingKeysWith: { first, _ in first })
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 百科正文。同一次运行里看过的条目不重复拉取。
    func entry(id: String) async throws -> EncyclopediaEntry {
        if let cached = entryCache[id] { return cached }
        guard let repository else { throw APIError.notConfigured }
        let fetched = try await repository.fetchEncyclopediaEntry(id: id)
        entryCache[id] = fetched
        return fetched
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
            structuredData: .question(QuestionRecordData(
                answered: true, answer: trimmed?.isEmpty == true ? nil : trimmed,
                // 整段替换 structured_data，从报告攒出来的问题要继续指着那份报告。
                reportID: Self.reportID(of: record)
            ))
        )
        await perform { _ = try await repository.updateRecord(recordID: record.id, draft: draft) }
    }

    private static func reportID(of record: RecordItem) -> UUID? {
        if case let .question(data) = record.structuredData { return data.reportID }
        return nil
    }

    /// 勾选 / 取消勾选一个清单条目。
    ///
    /// 已有记录就更新，没有才新建——否则同一个条目会攒出一堆记录，
    /// 进度算出来永远是错的。
    func toggleChecklistItem(collection: String, itemID: String) async {
        guard let repository else { return }
        let existing = checklistRecord(collection: collection, itemID: itemID)
        let nextDone = !(existing.map(isDone) ?? false)
        // 标题跟着记录一起存：人能读的名字在内容文件里，而记录只带 id。
        // 不存的话，记录列表和详情就只剩一个 slug 可显示。
        let itemTitle = collections[collection]?.items.first { $0.id == itemID }?.title
        let draft = RecordDraft(
            type: .checklist,
            occurredAt: existing?.occurredAt ?? .now,
            visibility: .family,
            title: itemTitle ?? existing?.title,
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

    /// 问诊结束后一次性把清单里的问题标记为已问。
    /// 逐条标记是此前唯一的方式，产检结束回来要点很多次。
    func markQuestionsAnswered(ids: [UUID]) async {
        guard let repository else { return }
        let targets = snapshot.records.filter { ids.contains($0.id) && $0.type == .question }
        for record in targets {
            let draft = RecordDraft(
                type: .question, occurredAt: record.occurredAt, visibility: record.visibility,
                title: record.title, content: record.content,
                structuredData: .question(QuestionRecordData(
                    answered: true, answer: nil, reportID: Self.reportID(of: record))))
            do {
                _ = try await repository.updateRecord(recordID: record.id, draft: draft)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await load()
    }

    /// 保存一条知识条目。已有 id 就是编辑，否则新建。
    func saveEntry(draft: RecordDraft, editing id: UUID?) async -> Bool {
        guard let repository else { return false }
        do {
            if let id {
                _ = try await repository.updateRecord(recordID: id, draft: draft)
            } else {
                _ = try await repository.createRecord(draft: draft)
            }
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 删除一条知识条目。资料库不该只能看——存错了、过时了要能删掉。
    func deleteEntry(id: UUID) async {
        guard let repository else { return }
        await perform { try await repository.deleteRecord(recordID: id) }
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
