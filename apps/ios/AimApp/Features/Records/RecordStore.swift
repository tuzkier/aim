import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class RecordStore {
    var snapshot: RecordSnapshot?
    var draft: RecordDraft?
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var repository: BusinessRepositoryProtocol?
    private var isAddingReportQuestions = false

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

    /// 带照片新建：先在主线程外把照片压到 2 MB 以内，逐张上传，再建记录并挂上上传得到的编号。
    /// 任何一张处理或上传失败都不建记录——少了照片的报告用户不一定会发现。
    func save(_ draft: RecordDraft, photos: [Data]) async -> Bool {
        guard !photos.isEmpty else { return await save(draft) }
        guard let repository else { errorMessage = APIError.notConfigured.localizedDescription; self.draft = draft; return false }
        self.draft = draft
        isSaving = true
        let jpegs = await Task.detached(priority: .userInitiated) {
            photos.map { UIImage(data: $0).flatMap(ImageCompression.jpegUnder2MB) }
        }.value
        var attachmentIDs: [UUID] = []
        do {
            for jpeg in jpegs {
                guard let jpeg else {
                    isSaving = false
                    errorMessage = "有一张照片处理不了，换一张试试。"
                    return false
                }
                attachmentIDs.append(try await repository.uploadAttachment(jpeg: jpeg))
            }
        } catch {
            isSaving = false
            errorMessage = "照片没能上传：\(error.localizedDescription)"
            return false
        }
        isSaving = false
        var withPhotos = draft
        withPhotos.attachmentIDs = attachmentIDs
        return await save(withPhotos)
    }

    /// 把报告上还没问过的异常项逐条加入「想问医生」，返回实际加了几条。
    /// 以当前快照判断哪些已经问过，所以连点两次不会重复加。
    func addQuestions(forReport report: RecordItem) async -> Int {
        guard !isAddingReportQuestions else { return 0 }
        isAddingReportQuestions = true
        defer { isAddingReportQuestions = false }
        // 记录页可能只加载了产检筛选，也可能保留着旧快照。先读全部可见记录，
        // 失败就保留错误供重试，不能把「没读到」当成「没有问题」。
        await load()
        guard errorMessage == nil else { return 0 }
        let drafts = CheckupReport.missingQuestions(for: report, in: snapshot?.records ?? [report], now: .now)
        var added = 0
        for draft in drafts {
            // 失败时 save 已经写好了错误信息；停下来，让用户重试剩下的。
            guard await save(draft) else { break }
            added += 1
        }
        return added
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
