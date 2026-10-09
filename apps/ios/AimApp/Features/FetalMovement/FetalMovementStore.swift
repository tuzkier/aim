import Foundation
import Observation

struct FetalMovementCompletion: Equatable, Sendable {
    let result: FetalMovementResult
    /// 这次之前的「平时」——必须在保存前取，否则这次会把自己算进平时里。
    let baselineSeconds: Int?
    let saved: Bool

    var isSlow: Bool {
        result.outcome == .reached
            && FetalMovementInsights.isSlow(durationSeconds: result.durationSeconds, baselineSeconds: baselineSeconds)
    }
}

/// 胎动计数的状态：进行中的计数（本地断点）、没保存上的结果、档案里的历史。
///
/// 进行中的计数与未保存的结果都写进 UserDefaults——计数可能持续两小时，
/// 中途被系统回收是常态，丢掉就等于让孕妈重数一遍。
///
/// 本地数据按「账号 + 孕期」分开存：换账号、换家庭后各自独立，
/// 切回来还能找到原来的断点和未保存结果，也不会把一家的计数存进另一家。
/// 调用方必须先 `bind(accountID:pregnancyID:)`，未绑定时所有计数操作都不生效。
@MainActor
@Observable
final class FetalMovementStore {
    var repository: BusinessRepositoryProtocol?
    var clock: () -> Date = { Date() }
    private(set) var sessions: [FetalMovementSession] = []
    private(set) var active: FetalMovementCounter?
    /// 没保存上的结果，旧的在前。按顺序重试，一条都不能丢。
    private(set) var unsaved: [FetalMovementResult] = []
    var errorMessage: String?

    let dedupeInterval: TimeInterval
    private let defaults: UserDefaults
    private var scope: Scope?
    private var isSaving = false

    private struct Scope: Equatable {
        let accountID: UUID
        let pregnancyID: UUID

        private var prefix: String { "aim.fetalMovement.\(accountID.uuidString).\(pregnancyID.uuidString)" }
        var activeKey: String { prefix + ".active" }
        var unsavedKey: String { prefix + ".unsaved" }
    }

    init(defaults: UserDefaults = .standard,
         dedupeInterval: TimeInterval = FetalMovementCounter.defaultDedupeInterval) {
        self.defaults = defaults
        self.dedupeInterval = dedupeInterval
    }

    /// 切到某个账号的某次孕期：读出它自己的断点与未保存结果，清空历史（随后由调用方 `load()`）。
    /// 同一作用域重复绑定不做任何事，避免每次刷新仓库都把历史清空一下。
    func bind(accountID: UUID, pregnancyID: UUID) {
        let next = Scope(accountID: accountID, pregnancyID: pregnancyID)
        guard next != scope else { return }
        scope = next
        active = Self.read(FetalMovementCounter.self, key: next.activeKey, from: defaults)
        unsaved = Self.read([FetalMovementResult].self, key: next.unsavedKey, from: defaults) ?? []
        sessions = []
        errorMessage = nil
    }

    var baselineSeconds: Int? { FetalMovementInsights.baselineSeconds(sessions) }
    var today: FetalMovementSession? { FetalMovementInsights.latest(onDayOf: clock(), in: sessions) }

    func load() async {
        do {
            try await reloadSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start() {
        guard let scope, active == nil else { return }
        active = FetalMovementCounter(startedAt: clock(), dedupeInterval: dedupeInterval)
        persist(scope)
    }

    func tap() -> FetalMovementCounter.TapResult {
        guard let scope, var counter = active else { return .ignored }
        let result = counter.tap(at: clock())
        active = counter
        persist(scope)
        return result
    }

    func finish() async -> FetalMovementCompletion? {
        guard let scope, let counter = active else { return nil }
        // 先落盘再做任何等待：结束时刻以按下为准，也防止等待期间被重复结束。
        let result = counter.result(at: clock())
        active = nil
        unsaved.append(result)
        persist(scope)
        // 还没拉过历史时先拉一次，否则「和平时比」会静默缺失。
        // 这次的结果还在本地队列里，拉回来的历史不含它——平时仍是保存前的平时。
        if sessions.isEmpty, repository != nil {
            try? await reloadSessions()
        }
        let baseline = baselineSeconds
        await saveUnsaved()
        return FetalMovementCompletion(
            result: result, baselineSeconds: baseline, saved: !unsaved.contains(result))
    }

    /// 按顺序保存队列里的结果；遇到失败就停下。全部保存成功返回 true。
    @discardableResult
    func saveUnsaved() async -> Bool {
        guard !isSaving else { return false }
        guard !unsaved.isEmpty else { return true }
        guard let repository, let scope else {
            errorMessage = "没保存上，重试"
            return false
        }
        isSaving = true
        defer { isSaving = false }

        while let result = unsaved.first, self.scope == scope {
            do {
                _ = try await repository.createRecord(draft: result.draft)
            } catch {
                if self.scope == scope { errorMessage = "没保存上，重试" }
                return false
            }
            removeSaved(result, from: scope)
        }
        // 保存途中切换了作用域：新作用域的队列这次没有动。
        guard self.scope == scope else { return false }
        errorMessage = nil
        // 已经保存成功，刷新历史失败不算错，不要让界面提示「没保存上」。
        try? await reloadSessions()
        return true
    }

    func discardActive() {
        guard let scope else { return }
        active = nil
        persist(scope)
    }

    func delete(_ session: FetalMovementSession) async {
        guard let repository else { return }
        do {
            try await repository.deleteRecord(recordID: session.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadSessions() async throws {
        guard let repository else { return }
        let requestedScope = scope
        let snapshot = try await repository.fetchRecords(type: .fetalMovement)
        // 拉取途中换了作用域，这份历史属于上一家，丢掉。
        guard scope == requestedScope else { return }
        sessions = snapshot.records
            .compactMap(FetalMovementSession.init(record:))
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// 只移除刚保存成功的那一条；作用域已切走时直接改它自己落盘的队列。
    private func removeSaved(_ result: FetalMovementResult, from savedScope: Scope) {
        if scope == savedScope {
            if let index = unsaved.firstIndex(of: result) { unsaved.remove(at: index) }
            persist(savedScope)
        } else {
            var queue = Self.read([FetalMovementResult].self, key: savedScope.unsavedKey, from: defaults) ?? []
            if let index = queue.firstIndex(of: result) { queue.remove(at: index) }
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
