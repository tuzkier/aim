import Foundation
import Observation

/// 宫缩计时的状态：进行中的计时（本地断点）、没保存上的结果、档案里的历史。
///
/// 计时可能持续好几个小时，中途被系统回收是常态，断点和未保存结果都写进 UserDefaults。
/// 本地数据按「账号 + 孕期」分开存，做法与 `FetalMovementStore` 相同；未绑定时所有操作都不生效。
@MainActor
@Observable
final class ContractionStore {
    var repository: BusinessRepositoryProtocol?
    var clock: () -> Date = { Date() }
    /// 孕周，由 App 在首页数据加载后设置；用于早产警示。
    var gestationalWeeks: Int?
    private(set) var active: ContractionTimer?
    private(set) var unsaved: [ContractionResult] = []
    private(set) var sessions: [ContractionSession] = []
    private(set) var isSaving = false
    /// 只放「没保存上，重试」：计时页底部据此显示重试。保存成功或队列清空时清掉。
    private(set) var saveError: String?
    /// 拉历史失败。和保存无关，不能在计时页冒充「没保存上」；历史加载成功时清掉。
    private(set) var loadError: String?

    private let defaults: UserDefaults
    /// 保存成功后在这里广播 `.aimDataChanged`。测试注入自己的，免得惊动宿主 App。
    private let notificationCenter: NotificationCenter
    private var scope: Scope?
    private var reloadGeneration = 0
    private var appliedReloadGeneration = 0

    private struct Scope: Equatable {
        let accountID: UUID
        let pregnancyID: UUID

        private var prefix: String { "aim.contraction.\(accountID.uuidString).\(pregnancyID.uuidString)" }
        var activeKey: String { prefix + ".active" }
        var unsavedKey: String { prefix + ".unsaved" }
    }

    init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    func bind(accountID: UUID, pregnancyID: UUID) {
        let next = Scope(accountID: accountID, pregnancyID: pregnancyID)
        guard next != scope else { return }
        scope = next
        active = Self.read(ContractionTimer.self, key: next.activeKey, from: defaults)
        unsaved = Self.read([ContractionResult].self, key: next.unsavedKey, from: defaults) ?? []
        sessions = []
        saveError = nil
        loadError = nil
    }

    /// 解绑时连仓库一起清掉：它按值带着上一家的身份。
    func unbind() {
        scope = nil
        repository = nil
        active = nil
        unsaved = []
        sessions = []
        saveError = nil
        loadError = nil
    }

    /// 实时档位：没有进行中的计时为 nil。
    var status: ContractionStatus? {
        active.map { ContractionMath.status($0, at: clock(), weeks: gestationalWeeks) }
    }

    /// 出发去医院前，结束计时的保存最多等这么久。
    static let tripSaveTimeout: Duration = .seconds(5)

    /// 最后一次结束超过 6 小时：先让用户选保存或丢弃，才能开始新的计时。
    var needsStaleDecision: Bool { active?.isStale(at: clock()) ?? false }
    var latest: ContractionSession? { sessions.first }

    func load() async {
        do { try await reloadSessions() } catch { loadError = error.localizedDescription }
    }

    @discardableResult
    func toggle() -> ContractionTimer.ToggleResult {
        guard let scope else { return .ignored }
        var timer = active ?? ContractionTimer()
        let result = timer.toggle(at: clock())
        active = timer.spans.isEmpty ? nil : timer
        persist(scope)
        return result
    }

    func removeLast() {
        guard let scope, var timer = active else { return }
        timer.removeLast()
        active = timer.spans.isEmpty ? nil : timer
        persist(scope)
    }

    /// 启动或回到前台时调用：宫缩中被杀掉超过 10 分钟的，截断为 10 分钟。
    func resumeAfterLaunch() {
        guard let scope, var timer = active else { return }
        timer.capRunning(at: clock())
        active = timer
        persist(scope)
    }

    func discardActive() {
        guard let scope else { return }
        active = nil
        persist(scope)
    }

    /// 结束计时并保存：没有已结束的宫缩时返回 nil 且什么都不做。
    /// 保存成功时 savedRecordID 为新记录的 id。进行中的那一次不存；
    /// 超出后端限制（1 天、500 次）的最早部分由 `ContractionTimer.archivedResult(id:)` 丢掉。
    func finish() async -> (result: ContractionResult, savedRecordID: UUID?)? {
        guard let result = enqueueActive() else { return nil }
        let savedID = await saveUnsaved(returning: result.id)
        return (result, savedID)
    }

    /// 结束计时并保存，但最多等 `timeout`：出发去医院时不能让家人卡在「正在保存…」。
    /// 超时就返回 `timedOut == true`、savedRecordID 为 nil；保存本身不取消，照常进行，
    /// 失败的留在队列里等补存。没有已结束的宫缩时返回 nil 且什么都不做。
    func finish(timeout: Duration) async -> (result: ContractionResult, savedRecordID: UUID?, timedOut: Bool)? {
        guard let result = enqueueActive() else { return nil }
        let saving = Task { await self.saveUnsaved(returning: result.id) }
        // 外层 nil 表示超时；内层是保存后的记录 id（没保存上也是 nil）。
        let outcome: UUID?? = await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            let timer = Task {
                try? await Task.sleep(for: timeout)
                once.resume(returning: nil)
            }
            Task {
                let savedID = await saving.value
                timer.cancel()
                once.resume(returning: .some(savedID))
            }
        }
        if let savedID = outcome { return (result, savedID, false) }
        return (result, nil, true)
    }

    /// 把进行中的计时收成待保存的结果：先落盘再等待，防止等待期间被重复结束，也保证杀掉 App 不丢。
    private func enqueueActive() -> ContractionResult? {
        guard let scope, let timer = active, let result = timer.archivedResult(id: UUID()) else { return nil }
        active = nil
        unsaved.append(result)
        persist(scope)
        return result
    }

    @discardableResult
    func saveUnsaved() async -> Bool {
        _ = await saveUnsaved(returning: nil)
        return unsaved.isEmpty
    }

    /// 按顺序保存队列；遇到失败就停。返回 `target` 那一条保存后的记录 id。
    private func saveUnsaved(returning target: UUID?) async -> UUID? {
        guard !isSaving else { return nil }
        guard !unsaved.isEmpty else {
            saveError = nil
            return nil
        }
        guard let repository, let scope else {
            saveError = "没保存上，重试"
            return nil
        }
        isSaving = true
        var targetRecordID: UUID?
        while let result = unsaved.first, self.scope == scope {
            do {
                let record = try await repository.createRecord(draft: result.draft)
                if result.id == target { targetRecordID = record.id }
            } catch {
                if self.scope == scope { saveError = "没保存上，重试" }
                isSaving = false
                return nil
            }
            removeSaved(result, from: scope)
        }
        isSaving = false
        guard self.scope == scope else { return targetRecordID }
        saveError = nil
        notificationCenter.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["record"]])
        await load()
        return targetRecordID
    }

    /// 只采用最新一次发出的请求，且绑定没变过；旧的、乱序回来的响应丢掉。
    private func reloadSessions() async throws {
        guard let repository, let requestedScope = scope else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        let snapshot: RecordSnapshot
        do {
            snapshot = try await repository.fetchRecords(type: .contraction)
        } catch {
            guard scope == requestedScope, generation == reloadGeneration else { return }
            throw error
        }
        guard scope == requestedScope, generation > appliedReloadGeneration else { return }
        appliedReloadGeneration = generation
        loadError = nil
        sessions = snapshot.records
            .compactMap(ContractionSession.init(record:))
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// 保存期间换了绑定：结果已经进了上一家的档案，从上一家落盘的队列里删掉，不碰当前的。
    private func removeSaved(_ result: ContractionResult, from savedScope: Scope) {
        if scope == savedScope {
            unsaved.removeAll { $0.id == result.id }
            persist(savedScope)
        } else {
            var queue = Self.read([ContractionResult].self, key: savedScope.unsavedKey, from: defaults) ?? []
            queue.removeAll { $0.id == result.id }
            Self.write(queue.isEmpty ? nil : queue, key: savedScope.unsavedKey, to: defaults)
        }
    }

    private func persist(_ scope: Scope) {
        Self.write(active, key: scope.activeKey, to: defaults)
        Self.write(unsaved.isEmpty ? nil : unsaved, key: scope.unsavedKey, to: defaults)
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func write<T: Encodable>(_ value: T?, key: String, to defaults: UserDefaults) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// 只让第一个结果生效：保存与超时谁先到用谁，后到的忽略。
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }

    func resume(returning value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
