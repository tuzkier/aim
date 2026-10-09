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
@MainActor
@Observable
final class FetalMovementStore {
    var repository: BusinessRepositoryProtocol?
    var clock: () -> Date = { Date() }
    private(set) var sessions: [FetalMovementSession] = []
    private(set) var active: FetalMovementCounter?
    private(set) var unsaved: FetalMovementResult?
    var errorMessage: String?

    let dedupeInterval: TimeInterval
    private let defaults: UserDefaults

    private enum Keys {
        static let active = "aim.fetalMovement.active"
        static let unsaved = "aim.fetalMovement.unsaved"
    }

    init(defaults: UserDefaults = .standard,
         dedupeInterval: TimeInterval = FetalMovementCounter.defaultDedupeInterval) {
        self.defaults = defaults
        self.dedupeInterval = dedupeInterval
        active = Self.read(FetalMovementCounter.self, key: Keys.active, from: defaults)
        unsaved = Self.read(FetalMovementResult.self, key: Keys.unsaved, from: defaults)
    }

    var baselineSeconds: Int? { FetalMovementInsights.baselineSeconds(sessions) }
    var today: FetalMovementSession? { FetalMovementInsights.latest(onDayOf: clock(), in: sessions) }

    func load() async {
        guard let repository else { return }
        do {
            let snapshot = try await repository.fetchRecords(type: .fetalMovement)
            sessions = snapshot.records
                .compactMap(FetalMovementSession.init(record:))
                .sorted { $0.startedAt > $1.startedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start() {
        guard active == nil else { return }
        active = FetalMovementCounter(startedAt: clock(), dedupeInterval: dedupeInterval)
        persist()
    }

    func tap() -> FetalMovementCounter.TapResult {
        guard var counter = active else { return .ignored }
        let result = counter.tap(at: clock())
        active = counter
        persist()
        return result
    }

    func finish() async -> FetalMovementCompletion? {
        guard let counter = active else { return nil }
        let baseline = baselineSeconds
        let result = counter.result(at: clock())
        active = nil
        unsaved = result
        persist()
        let saved = await saveUnsaved()
        return FetalMovementCompletion(result: result, baselineSeconds: baseline, saved: saved)
    }

    @discardableResult
    func saveUnsaved() async -> Bool {
        guard let result = unsaved, let repository else { return false }
        do {
            _ = try await repository.createRecord(draft: result.draft)
            unsaved = nil
            errorMessage = nil
            persist()
            await load()
            return true
        } catch {
            errorMessage = "没保存上，重试"
            return false
        }
    }

    func discardActive() {
        active = nil
        persist()
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

    private func persist() {
        Self.write(active, key: Keys.active, to: defaults)
        Self.write(unsaved, key: Keys.unsaved, to: defaults)
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
