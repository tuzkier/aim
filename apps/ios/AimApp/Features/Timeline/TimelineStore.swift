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

    /// 首页各分组的「现在」。与 `today`（服务端 as_of，用于孕周换算）分开：
    /// as_of 是日期不是时刻，用它判断「今天 20:00 是否已过」会出错。
    var now: Date = .now

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

    // MARK: - 首页派生

    var stageName: String? {
        guard let week = currentWeek else { return nil }
        if week <= 13 { return "孕早期" }
        if week <= 27 { return "孕中期" }
        return "孕晚期"
    }

    private var endOfToday: Date { TaskDateText.endOfDay(now) }
    private var startOfToday: Date { TimelineBuilder.calendar.startOfDay(for: now) }

    /// 未完成任务按截止时间升序，没有截止时间的排最后。
    private var openTasksByDue: [TaskItem] {
        tasks.filter(\.isOpen).sorted { lhs, rhs in
            switch (lhs.dueAt, rhs.dueAt) {
            case let (l?, r?): return l < r
            case (nil, nil): return lhs.id.uuidString < rhs.id.uuidString
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    /// 逾期或今天截止的最早一条；没有就是所有未完成里最早的；都没有就不显示焦点卡。
    var focusTask: TaskItem? {
        let open = openTasksByDue
        if let dueSoon = open.first(where: { ($0.dueAt ?? .distantFuture) <= endOfToday }) { return dueSoon }
        return open.first
    }

    func isOverdue(_ task: TaskItem) -> Bool {
        guard let due = task.dueAt else { return false }
        return due < startOfToday
    }

    /// 今天组：截止 ≤ 今天 23:59 或没有截止时间，排除焦点任务。逾期自然排在最前。
    var todayTasks: [TaskItem] {
        let focusID = focusTask?.id
        return openTasksByDue.filter { task in
            task.id != focusID && (task.dueAt.map { $0 <= endOfToday } ?? true)
        }
    }

    var overdueCount: Int { todayTasks.filter(isOverdue).count }

    /// 接下来 7 天：明天 00:00 到第 7 天 23:59。
    var upcomingTasks: [TaskItem] {
        let focusID = focusTask?.id
        guard let seventh = TimelineBuilder.calendar.date(byAdding: .day, value: 7, to: startOfToday) else { return [] }
        let windowEnd = TaskDateText.endOfDay(seventh)
        return openTasksByDue.filter { task in
            guard task.id != focusID, let due = task.dueAt else { return false }
            return due > endOfToday && due <= windowEnd
        }
    }

    var recentRecords: [RecordItem] {
        Array(records.sorted { $0.occurredAt > $1.occurredAt }.prefix(3))
    }

    var pastWeeks: [TimelineWeek] { weeks.filter { $0.position == .past } }

    @discardableResult
    func createTask(title: String, description: String? = nil, dueAt: Date?, assignedMemberID: UUID? = nil) async -> Bool {
        guard let repository else { return false }
        do {
            _ = try await repository.createTask(
                title: title, description: description, dueAt: dueAt, assignedMemberID: assignedMemberID)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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

            now = .now
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

    @discardableResult
    func complete(_ task: TaskItem) async -> Bool {
        guard let repository else { return false }
        do {
            _ = try await repository.complete(task: task)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
            FamilyMember(accountID: motherID, role: .mother, nickname: nil, status: "active", joinedAt: nil),
            FamilyMember(accountID: UUID(), role: .father, nickname: nil, status: "active", joinedAt: nil)
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
