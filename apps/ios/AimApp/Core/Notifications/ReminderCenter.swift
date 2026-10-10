import Foundation
import Observation
import UIKit
@preconcurrency import UserNotifications

enum ReminderAuthorization: Equatable { case notDetermined, allowed, denied }

@MainActor
protocol ReminderCenterProtocol {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async throws -> Bool
    func pendingIDs() async -> [String]
    func add(_ reminder: PlannedReminder) async throws
    func remove(_ identifiers: [String])
}

@MainActor
final class SystemReminderCenter: ReminderCenterProtocol {
    private let center = UNUserNotificationCenter.current()
    func authorization() async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .allowed
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }
    func pendingIDs() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }

    static func request(for reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.isTest ? "Aim 测试提醒" : reminder.route.kind.title
        content.body = reminder.isTest ? "点击这里打开本周简报。" : reminder.route.kind.body
        content.sound = .default
        content.userInfo = reminder.route.userInfo
        content.threadIdentifier = "aim.reminders"
        let parts = ReminderPlanner.calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: reminder.fireAt)
        return UNNotificationRequest(identifier: reminder.id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }
    func add(_ reminder: PlannedReminder) async throws { try await center.add(Self.request(for: reminder)) }
    func remove(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

struct PendingReminder: Equatable, Identifiable {
    let id = UUID()
    let route: ReminderRoute
}

@MainActor
@Observable
final class ReminderCoordinator {
    static let shared = ReminderCoordinator(center: SystemReminderCenter())
    private(set) var scope: ReminderScope?
    private(set) var preferences = ReminderPreferences()
    private(set) var authorization = ReminderAuthorization.notDetermined
    private(set) var scheduled: [PlannedReminder] = []
    private(set) var isUpdating = false
    var errorMessage: String?
    var pendingRoute: PendingReminder?
    var clock: () -> Date = { .now }
    private let center: ReminderCenterProtocol
    private let defaults: UserDefaults
    private var repository: BusinessRepositoryProtocol?
    private var generation = 0
    private var scopeRevision = 0
    private var running = false
    private var needsRefresh = false
    private var knownIDs: [String]
    private var activeCount: Date?
    private var didBind = false
    private var observations: [ReminderObservation] = []
    private static let idsKey = "aim.reminders.pendingIDs"

    init(center: ReminderCenterProtocol, defaults: UserDefaults = .standard,
         notificationCenter: NotificationCenter = .default) {
        self.center = center; self.defaults = defaults
        knownIDs = defaults.stringArray(forKey: Self.idsKey) ?? []
        observations = [
            ReminderObservation(center: notificationCenter,
                token: notificationCenter.addObserver(forName: .aimReminderScopeChanged, object: nil, queue: .main) {
                    [weak self] note in
                    MainActor.assumeIsolated { self?.bind(note.userInfo?["scope"] as? ReminderScope) }
                }),
            ReminderObservation(center: notificationCenter,
                token: notificationCenter.addObserver(forName: .aimDataChanged, object: nil, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.preferences.enabled else { return }
                        await self.refresh(activeCount: self.activeCount)
                    }
                }),
        ]
    }

    func bind(_ next: ReminderScope?, repository: BusinessRepositoryProtocol? = nil) {
        if didBind && scope == next { if let repository { self.repository = repository }; return }
        didBind = true
        scopeRevision += 1
        generation += 1
        center.remove(knownIDs)
        knownIDs = []; scheduled = []; activeCount = nil
        defaults.removeObject(forKey: Self.idsKey)
        scope = next; self.repository = repository
        preferences = next.flatMap { current in
            defaults.data(forKey: preferenceKey(current.accountID))
                .flatMap { try? JSONDecoder().decode(ReminderPreferences.self, from: $0) }
        } ?? ReminderPreferences()
        if !preferences.isValid { preferences = ReminderPreferences() }
        if let pendingRoute, let next, pendingRoute.route.scope != next { self.pendingRoute = nil }
        if next == nil { pendingRoute = nil }
        let revision = generation
        Task {
            let identifiers = await center.pendingIDs()
            guard revision == generation else { return }
            let keep = next.map { ReminderPlanner.prefix + $0.key + "." }
            center.remove(identifiers.filter {
                $0.hasPrefix(ReminderPlanner.prefix) && (keep == nil || !$0.hasPrefix(keep!))
            })
        }
    }

    func setRepository(_ repository: BusinessRepositoryProtocol) { self.repository = repository }

    func save(_ prefs: ReminderPreferences) async -> Bool {
        guard let current = scope else { errorMessage = "请先登录并建立孕期档案"; return false }
        guard prefs.isValid else { errorMessage = "免打扰的起止时间不能相同"; return false }
        errorMessage = nil
        let revision = scopeRevision
        authorization = await center.authorization()
        if prefs.enabled && authorization == .notDetermined {
            do { _ = try await center.requestAuthorization(); authorization = await center.authorization() }
            catch { errorMessage = "暂时没能申请通知权限，请重试"; return false }
        }
        guard scope == current, revision == scopeRevision else { return false }
        if prefs.enabled && authorization != .allowed {
            errorMessage = "系统通知已关闭，请在系统设置中允许 Aim 发送通知"
            return false
        }
        preferences = prefs
        defaults.set(try? JSONEncoder().encode(prefs), forKey: preferenceKey(current.accountID))
        await refresh(activeCount: activeCount)
        return true
    }

    /// 每次读取前先取消旧计划；读取失败就不会用旧截止时间继续催用户。
    func refresh() async { await refresh(activeCount: activeCount) }

    func refresh(activeCount: Date?) async {
        self.activeCount = activeCount
        generation += 1
        needsRefresh = true
        center.remove(knownIDs)
        knownIDs = []; scheduled = []
        defaults.removeObject(forKey: Self.idsKey)
        guard !running else { return }
        running = true; isUpdating = true
        defer { running = false; isUpdating = false }
        while needsRefresh {
            needsRefresh = false
            let revision = generation
            let current = scope
            let ids = await center.pendingIDs()
            guard revision == generation else { needsRefresh = true; continue }
            center.remove(ids.filter { $0.hasPrefix(ReminderPlanner.prefix) })
            authorization = await center.authorization()
            guard revision == generation else { needsRefresh = true; continue }
            guard let current, preferences.enabled, authorization == .allowed, let repository else { continue }
            do {
                async let pregnancy = repository.fetchPregnancy()
                async let plan = repository.fetchPlan()
                async let records = repository.fetchRecords(type: nil)
                let snapshot = try await (pregnancy, plan, records)
                guard revision == generation, scope == current else { needsRefresh = true; continue }
                guard let pregnancy = snapshot.0, pregnancy.id == current.pregnancyID,
                      snapshot.1.pregnancyID == current.pregnancyID else {
                    errorMessage = "当前孕期档案暂时无法读取，请重试"
                    continue
                }
                let planned = ReminderPlanner.make(scope: current, preferences: preferences,
                    pregnancy: pregnancy, tasks: snapshot.1.tasks, records: snapshot.2.records,
                    activeCount: self.activeCount, now: clock())
                for reminder in planned {
                    guard revision == generation else { needsRefresh = true; break }
                    try await center.add(reminder)
                    guard revision == generation, scope == current else {
                        center.remove([reminder.id]); needsRefresh = true; break
                    }
                    knownIDs.append(reminder.id)
                    scheduled.append(reminder)
                    defaults.set(knownIDs, forKey: Self.idsKey)
                }
                if revision == generation { errorMessage = nil }
            } catch {
                guard revision == generation else { needsRefresh = true; continue }
                center.remove(knownIDs); knownIDs = []; scheduled = []
                defaults.removeObject(forKey: Self.idsKey)
                errorMessage = "提醒暂时没能更新，请重新打开 App 或重试"
            }
        }
    }

    func refreshPermission() async { authorization = await center.authorization() }

    func sendTest() async -> Bool {
        guard let current = scope, preferences.enabled, await center.authorization() == .allowed else {
            errorMessage = "请先开启提醒并允许系统通知"; return false
        }
        let revision = generation
        let request = PlannedReminder(id: ReminderPlanner.prefix + current.key + ".test",
            fireAt: clock().addingTimeInterval(10), route: ReminderRoute(scope: current, kind: .weekly), isTest: true)
        do {
            try await center.add(request)
            guard scope == current, revision == generation else { center.remove([request.id]); return false }
            knownIDs.append(request.id); defaults.set(knownIDs, forKey: Self.idsKey)
            return true
        } catch { errorMessage = "测试提醒没能发送，请重试"; return false }
    }

    func receive(_ route: ReminderRoute) {
        if let scope, scope != route.scope { return }
        pendingRoute = PendingReminder(route: route)
    }
    func mayPresent(_ route: ReminderRoute) -> Bool {
        route.scope == scope && preferences.enabled && !preferences.isQuiet(clock())
    }
    private func preferenceKey(_ account: UUID) -> String { "aim.reminders.preferences." + account.uuidString }
}

private final class ReminderObservation: @unchecked Sendable {
    let center: NotificationCenter
    let token: any NSObjectProtocol
    init(center: NotificationCenter, token: any NSObjectProtocol) { self.center = center; self.token = token }
    deinit { center.removeObserver(token) }
}

extension Notification.Name {
    static let aimReminderScopeChanged = Notification.Name("aim.reminders.scopeChanged")
}

final class ReminderAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let route = ReminderRoute(userInfo: response.notification.request.content.userInfo)
        Task { @MainActor in
            if let route { ReminderCoordinator.shared.receive(route) }
            completionHandler()
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let route = ReminderRoute(userInfo: notification.request.content.userInfo)
        Task { @MainActor in
            completionHandler(route.map { ReminderCoordinator.shared.mayPresent($0) } == true ? [.banner, .sound] : [])
        }
    }
}
