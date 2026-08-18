import Foundation
import Observation

enum TimelineEntryKind: Equatable {
    case task
    case record(RecordType)
}

enum TimelineFilter: String, CaseIterable, Hashable {
    case all
    case tasks
    case checkup
    case symptom
    case note

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .tasks: return "待办"
        case .checkup: return "产检"
        case .symptom: return "身体感受"
        case .note: return "随手记"
        }
    }

    func accepts(entryKind: TimelineEntryKind) -> Bool {
        switch (self, entryKind) {
        case (.all, _): return true
        case (.tasks, .task): return true
        case (.tasks, .record): return false
        case (_, .task): return false
        case let (.checkup, .record(type)): return type == .checkup
        case let (.symptom, .record(type)): return type == .symptom
        case let (.note, .record(type)): return type == .note
        }
    }
}

@MainActor
@Observable
final class TimelineStore {
    var weeks: [TimelineWeek] = []
    var filter: TimelineFilter = .all { didSet { rebuild() } }
    var isLoading = false
    var errorMessage: String?
    var familyMembers: [FamilyMember] = []

    var repository: BusinessRepositoryProtocol?

    var tasks: [TaskItem] = []
    var records: [RecordItem] = []
    var lastMenstrualPeriod: Date?
    var today: Date = .now
    var currentDays: Int = 0

    var currentWeek: Int? {
        weeks.first { $0.position == .current }?.week
    }

    var expandedFarWeeks: Set<Int> = []

    func isCollapsed(_ week: TimelineWeek) -> Bool {
        guard let current = currentWeek else { return false }
        guard week.position == .future, week.week > current + 4 else { return false }
        return !expandedFarWeeks.contains(week.week)
    }

    func expand(_ week: TimelineWeek) {
        expandedFarWeeks.insert(week.week)
    }

    var focusTask: TaskItem? {
        guard let current = weeks.first(where: { $0.position == .current }) else { return nil }
        return current.entries.compactMap { entry -> TaskItem? in
            if case let .task(item) = entry, item.isOpen { return item }
            return nil
        }.first
    }

    func assigneeName(for memberID: UUID?) -> String? {
        guard let memberID else { return nil }
        return familyMembers.first { $0.accountID == memberID }?.role.displayName
    }

    func load() async {
        guard let repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let todaySnapshot = try await repository.fetchToday()
            let plan = try await repository.fetchPlan()
            let recordsSnapshot = try await repository.fetchRecords(type: nil)
            let family = try await repository.fetchFamily()

            today = todaySnapshot.asOf
            currentDays = todaySnapshot.days
            lastMenstrualPeriod = TimelineBuilder.lastMenstrualPeriod(
                asOf: todaySnapshot.asOf,
                weeks: todaySnapshot.weeks,
                days: todaySnapshot.days
            )
            tasks = plan.tasks
            records = recordsSnapshot.records
            familyMembers = family.members
            errorMessage = nil
            rebuild()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func complete(_ task: TaskItem) async {
        guard let repository else { return }
        do {
            _ = try await repository.complete(task: task)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rebuild() {
        guard let lastMenstrualPeriod else { return }
        let filteredTasks = filter.accepts(entryKind: .task) ? tasks : []
        let filteredRecords = records.filter { filter.accepts(entryKind: .record($0.type)) }
        weeks = TimelineBuilder.build(
            tasks: filteredTasks,
            records: filteredRecords,
            lastMenstrualPeriod: lastMenstrualPeriod,
            today: today
        )
    }
}

extension TimelineStore {
    static func preview() -> TimelineStore {
        let store = TimelineStore()
        let calendar = PregnancyDateCalculator.calendar
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 9))!
        let motherID = UUID()
        store.familyMembers = [
            FamilyMember(accountID: motherID, role: .mother, status: "active", joinedAt: nil),
            FamilyMember(accountID: UUID(), role: .father, status: "active", joinedAt: nil)
        ]
        store.tasks = [
            TaskItem(id: UUID(), title: "核对检查所需材料", detail: "检查日期确定后，需要提前核对证件和既往资料。",
                     status: .todo, version: 1,
                     dueAt: calendar.date(byAdding: .hour, value: 1, to: today), scheduledFor: nil,
                     assignedMemberID: motherID, changedByActor: .agent),
            TaskItem(id: UUID(), title: "晚饭后散步 20 分钟", detail: nil, status: .todo, version: 1,
                     dueAt: calendar.date(byAdding: .hour, value: 10, to: today), scheduledFor: nil,
                     assignedMemberID: motherID, changedByActor: .system)
        ]
        store.records = []
        store.today = today
        store.lastMenstrualPeriod = TimelineBuilder.lastMenstrualPeriod(asOf: today, weeks: 18, days: 3)
        store.rebuild()
        return store
    }
}
