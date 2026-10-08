import Foundation
import Observation

/// 首页的数据：孕期、本周内容、今天的待办、家里最近的动态。
///
/// 各块独立加载、独立报错：家庭动态拿不到，不该连孕周主卡一起空白。
@MainActor
@Observable
final class HomeDashboardStore {
    var repository: BusinessRepositoryProtocol?
    var cache = WeeklyContentCache()

    var pregnancy: PregnancySummary?
    var book: WeeklyContentBook?
    var todayTasks: [TaskItem] = []
    var todayTotal = 0
    var nextTask: TaskItem?
    var recentActivity: [FamilyActivityItem] = []
    var members: [FamilyMember] = []

    var pregnancyError: String?
    var tasksError: String?
    var activityError: String?
    var isLoading = false

    var progress: PregnancyProgress? { pregnancy.map { PregnancyProgress(weeks: $0.weeks, days: $0.days) } }

    var thisWeek: WeekContent? {
        guard let pregnancy else { return nil }
        return book?.content(forWeek: pregnancy.weeks)
    }

    func load(now: Date = .now) async {
        guard let repository else { return }
        if book == nil { book = cache.load() }
        isLoading = true
        defer { isLoading = false }

        async let pregnancyResult = Self.capture { try await repository.fetchPregnancy() }
        async let planResult = Self.capture { try await repository.fetchPlan() }
        async let familyResult = Self.capture { try await repository.fetchFamily() }
        async let activityResult = Self.capture { try await repository.fetchActivity(before: nil) }
        async let bookResult = Self.capture { try await repository.fetchWeeklyContent() }

        switch await pregnancyResult {
        case let .success(value): pregnancy = value; pregnancyError = nil
        case let .failure(error): pregnancyError = error.localizedDescription
        }
        switch await planResult {
        case let .success(plan):
            let selection = Self.todaySelection(tasks: plan.tasks, now: now)
            todayTasks = selection.shown
            todayTotal = selection.total
            nextTask = selection.next
            tasksError = nil
        case let .failure(error):
            tasksError = error.localizedDescription
        }
        if case let .success(family) = await familyResult { members = family.members }
        switch await activityResult {
        case let .success(page): recentActivity = Array(page.items.prefix(2)); activityError = nil
        case let .failure(error): activityError = error.localizedDescription
        }
        if case let .success(fresh) = await bookResult {
            book = fresh
            try? cache.save(fresh)
        }
    }

    /// 首页勾选完成：成功后重新加载「今天」。
    func complete(_ task: TaskItem) async -> Bool {
        guard let repository else { return false }
        do {
            _ = try await repository.complete(task: task)
            if let plan = try? await repository.fetchPlan() {
                let selection = Self.todaySelection(tasks: plan.tasks, now: .now)
                todayTasks = selection.shown
                todayTotal = selection.total
                nextTask = selection.next
            }
            return true
        } catch {
            tasksError = error.localizedDescription
            return false
        }
    }

    private static func capture<T>(_ work: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    // MARK: - 纯函数

    /// 「今天」与待办页同一口径：今天截止、已逾期、没有截止时间的未完成待办，按截止时间排序（逾期在前）。
    /// 首页只显示前 3 项；一项都没有时给出最近的一件将来的待办。
    nonisolated static func todaySelection(tasks: [TaskItem], now: Date) -> (shown: [TaskItem], total: Int, next: TaskItem?) {
        let endOfToday = TaskDateText.endOfDay(now)
        let open = tasks.filter(\.isOpen).sorted { lhs, rhs in
            switch (lhs.dueAt, rhs.dueAt) {
            case let (l?, r?): return l < r
            case (nil, nil): return lhs.title < rhs.title
            case (nil, _): return false
            case (_, nil): return true
            }
        }
        let today = open.filter { ($0.dueAt.map { $0 <= endOfToday }) ?? true }
        let next = today.isEmpty ? open.first { ($0.dueAt ?? .distantPast) > endOfToday } : nil
        return (Array(today.prefix(3)), today.count, next)
    }

    nonisolated static func greeting(at date: Date) -> String {
        let hour = TimelineBuilder.calendar.component(.hour, from: date)
        switch hour {
        case 5..<11: return "早上好"
        case 11..<13: return "中午好"
        case 13..<18: return "下午好"
        default: return "晚上好"
        }
    }
}
