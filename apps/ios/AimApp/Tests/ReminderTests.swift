import XCTest
import UserNotifications
@testable import AimApp

@MainActor
final class ReminderTests: XCTestCase {
    private let scope = ReminderScope(accountID: UUID(), familyID: UUID(), pregnancyID: UUID())
    private let now = ISO8601DateFormatter().date(from: "2026-10-10T10:00:00+08:00")!
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var pregnancy: PregnancySummary {
        PregnancySummary(id: scope.pregnancyID, dueDate: date("2027-01-02T00:00:00+08:00"), weeks: 28, days: 0)
    }
    private var prefs: ReminderPreferences { var p = ReminderPreferences(); p.enabled = true; return p }
    private func task(due: Date?, scheduled: Date? = nil, member: UUID? = nil,
                      status: TaskStatus = .todo, id: UUID = UUID()) -> TaskItem {
        TaskItem(id: id, title: "不应展示在锁屏的医疗事项", detail: "私有详情", status: status,
                 version: 1, dueAt: due, scheduledFor: scheduled, assignedMemberID: member, changedByActor: .account)
    }
    private func plan(_ tasks: [TaskItem] = [], records: [RecordItem] = [],
                      pregnancy: PregnancySummary? = nil, prefs: ReminderPreferences? = nil,
                      active: Date? = nil) -> [PlannedReminder] {
        ReminderPlanner.make(scope: scope, preferences: prefs ?? self.prefs,
            pregnancy: pregnancy ?? self.pregnancy, tasks: tasks, records: records, activeCount: active, now: now)
    }

    func testDisabledAndInvalidPreferencesScheduleNothing() {
        XCTAssertTrue(plan(prefs: ReminderPreferences()).isEmpty)
        var p = prefs; p.quietEnd = p.quietStart
        XCTAssertTrue(plan(prefs: p).isEmpty)
        p.quietEnd = 8 * 60; p.fetalMinute = 1440
        XCTAssertTrue(plan(prefs: p).isEmpty)
    }

    func testPostpartumStopsFetalRemindersAndCancelledPrenatalTasks() {
        var born = pregnancy
        born.status = "postpartum"; born.birthDate = now
        let cancelled = task(due: now.addingTimeInterval(7200), status: .cancelled)
        let current = task(due: now.addingTimeInterval(10800))
        let result = plan([cancelled, current], pregnancy: born)
        XCTAssertFalse(result.contains { $0.route.kind == .fetalMovement })
        XCTAssertFalse(result.contains { $0.route.taskID == cancelled.id })
        XCTAssertTrue(result.contains { $0.route.taskID == current.id })
    }
    func testOnlyUpcomingOpenTasksForMeOrUnassignedAreScheduled() {
        let future = now.addingTimeInterval(7200)
        let items = [task(due: future), task(due: future, member: scope.accountID),
                     task(due: future, member: UUID()), task(due: future, status: .completed),
                     task(due: future, status: .unknown), task(due: nil), task(due: now)]
        let result = plan(items).filter { $0.route.kind == .task }
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.fireAt == future.addingTimeInterval(-3600) })
        XCTAssertFalse(result[0].route.kind.body.contains(items[0].title))
    }
    func testChangedDueDateOverridesTheOldScheduledDate() {
        let moved = task(due: now.addingTimeInterval(90000), scheduled: now.addingTimeInterval(7200))
        let result = plan([moved]).first { $0.route.kind == .task }!
        XCTAssertEqual(result.fireAt, moved.dueAt!.addingTimeInterval(-3600))
    }

    func testTaskCreatedWithinAnHourStillGetsAnOnTimeReminder() {
        let imminent = task(due: now.addingTimeInterval(1800))
        let result = plan([imminent]).first { $0.route.kind == .task }
        XCTAssertEqual(result?.fireAt, imminent.dueAt)
        XCTAssertFalse(plan([task(due: now.addingTimeInterval(-1))]).contains { $0.route.kind == .task })
    }
    func testQuietHoursAdvanceDeadlinesAndDelayRoutineReminders() {
        let night = date("2026-10-10T23:00:00+08:00")
        XCTAssertEqual(ReminderPlanner.avoidingQuiet(night, prefs, beforeDeadline: true),
                       date("2026-10-10T21:59:00+08:00"))
        XCTAssertEqual(ReminderPlanner.avoidingQuiet(night, prefs, beforeDeadline: false),
                       date("2026-10-11T08:00:00+08:00"))
        let morning = date("2026-10-11T03:00:00+08:00")
        XCTAssertEqual(ReminderPlanner.avoidingQuiet(morning, prefs, beforeDeadline: true),
                       date("2026-10-10T21:59:00+08:00"))
        var daytime = prefs; daytime.quietStart = 12 * 60; daytime.quietEnd = 14 * 60
        XCTAssertEqual(ReminderPlanner.avoidingQuiet(date("2026-10-10T13:00:00+08:00"), daytime,
                                                    beforeDeadline: false), date("2026-10-10T14:00:00+08:00"))
        XCTAssertFalse(prefs.isQuiet(date("2026-10-11T08:00:00+08:00")))
    }
    func testFetalReminderStartsAt28WeeksAndStopsAfter42() {
        let today = ReminderPlanner.calendar.startOfDay(for: now)
        let dueAt28 = ReminderPlanner.calendar.date(byAdding: .day, value: 84, to: today)!
        let p28 = PregnancySummary(id: scope.pregnancyID, dueDate: dueAt28, weeks: 28, days: 0)
        XCTAssertTrue(plan(pregnancy: p28).contains { $0.route.kind == .fetalMovement && ReminderPlanner.calendar.isDate($0.fireAt, inSameDayAs: now) })
        let p27 = PregnancySummary(id: scope.pregnancyID, dueDate: dueAt28.addingTimeInterval(86400), weeks: 27, days: 6)
        XCTAssertFalse(plan(pregnancy: p27).contains { $0.route.kind == .fetalMovement && ReminderPlanner.calendar.isDate($0.fireAt, inSameDayAs: now) })
        let p43 = PregnancySummary(id: scope.pregnancyID, dueDate: today.addingTimeInterval(-21 * 86400), weeks: 43, days: 0)
        XCTAssertFalse(plan(pregnancy: p43).contains { $0.route.kind == .fetalMovement })
    }
    func testActiveCountSuppressesOnlyItsCalendarDay() {
        let all = plan().filter { $0.route.kind == .fetalMovement }
        let active = plan(active: now).filter { $0.route.kind == .fetalMovement }
        XCTAssertEqual(active.count, all.count - 1)
        XCTAssertFalse(active.contains { ReminderPlanner.calendar.isDate($0.fireAt, inSameDayAs: now) })
    }

    func testTodaysRecordSuppressesReminderButAnotherPregnancyDoesNot() {
        func record(pregnancyID: UUID) -> RecordItem {
            RecordItem(id: UUID(), pregnancyID: pregnancyID, familyID: scope.familyID,
                authorAccountID: scope.accountID, type: .fetalMovement, occurredAt: now, visibility: .family,
                title: nil, content: nil, structuredData: .unknown, attachmentRefs: [], createdAt: now, updatedAt: now)
        }
        let same = plan(records: [record(pregnancyID: scope.pregnancyID)])
        XCTAssertFalse(same.contains { $0.route.kind == .fetalMovement && ReminderPlanner.calendar.isDate($0.fireAt, inSameDayAs: now) })
        let other = plan(records: [record(pregnancyID: UUID())])
        XCTAssertTrue(other.contains { $0.route.kind == .fetalMovement && ReminderPlanner.calendar.isDate($0.fireAt, inSameDayAs: now) })
    }
    func testBudgetIsBoundedAndClosestDatesComeFirstWithoutDuplicateIDs() {
        let tasks = (1...100).map { task(due: now.addingTimeInterval(Double($0) * 4000)) }
        let result = plan(tasks)
        XCTAssertEqual(result.count, 60)
        XCTAssertEqual(Set(result.map(\.id)).count, result.count)
        XCTAssertEqual(result.map(\.fireAt), result.map(\.fireAt).sorted())
    }
    func testWeeklyReminderUsesMondayAndRouteRequiresScopeAndTaskID() {
        let weekly = plan().filter { $0.route.kind == .weekly }
        XCTAssertFalse(weekly.isEmpty)
        XCTAssertTrue(weekly.allSatisfy { ReminderPlanner.calendar.component(.weekday, from: $0.fireAt) == 2 })
        let route = ReminderRoute(scope: scope, kind: .task, taskID: UUID())
        XCTAssertEqual(ReminderRoute(userInfo: route.userInfo), route)
        var invalid = route.userInfo; invalid.removeValue(forKey: "account_id")
        XCTAssertNil(ReminderRoute(userInfo: invalid))
        invalid = route.userInfo; invalid["task_id"] = "bad"
        XCTAssertNil(ReminderRoute(userInfo: invalid))
    }
    func testSystemRequestHasNonRepeatingCalendarTriggerAndGenericContent() {
        let future = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970) + 3600)
        let reminder = PlannedReminder(id: "test-calendar", fireAt: future,
                                      route: ReminderRoute(scope: scope, kind: .task, taskID: UUID()))
        let request = SystemReminderCenter.request(for: reminder)
        let trigger = request.trigger as! UNCalendarNotificationTrigger
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.nextTriggerDate(), reminder.fireAt)
        XCTAssertFalse(request.content.body.contains("医疗事项"))
        XCTAssertEqual(ReminderRoute(userInfo: request.content.userInfo), reminder.route)
    }

    private func fixture() -> (ReminderCoordinator, FakeReminderCenter, ReminderRepository, UserDefaults) {
        let defaults = UserDefaults(suiteName: "reminders-test-\(UUID())")!
        let center = FakeReminderCenter()
        let repo = ReminderRepository(pregnancy: pregnancy, scope: scope)
        let service = ReminderCoordinator(center: center, defaults: defaults, notificationCenter: NotificationCenter())
        service.clock = { self.now }
        service.bind(scope, repository: repo)
        return (service, center, repo, defaults)
    }
    func testPermissionDeniedDoesNotPretendNotificationsAreEnabled() async {
        let (service, center, _, _) = fixture()
        center.permission = .notDetermined; center.grant = false
        let saved = await service.save(prefs)
        XCTAssertFalse(saved)
        XCTAssertFalse(service.preferences.enabled)
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertNotNil(service.errorMessage)
    }
    func testForegroundRefreshDuringPermissionPromptDoesNotLoseTheSave() async {
        let (service, center, _, _) = fixture()
        center.permission = .notDetermined
        center.duringPermission = { await service.refresh() }
        let saved = await service.save(prefs)
        XCTAssertTrue(saved)
        XCTAssertTrue(service.preferences.enabled)
        XCTAssertFalse(center.pending.isEmpty)
    }
    func testCompletionAndReschedulingReplacePendingTaskRequests() async {
        let (service, center, repo, _) = fixture()
        let original = task(due: now.addingTimeInterval(7200))
        repo.tasks = [original]
        let saved = await service.save(prefs)
        XCTAssertTrue(saved)
        let old = center.pending.values.first { $0.route.kind == .task }!
        repo.tasks = [task(due: now.addingTimeInterval(90000), scheduled: original.dueAt, id: original.id)]
        await service.refresh()
        let moved = center.pending[old.id]!
        XCTAssertNotEqual(moved.fireAt, old.fireAt)
        repo.tasks = [task(due: original.dueAt, status: .completed, id: original.id)]
        await service.refresh()
        XCTAssertNil(center.pending[old.id])
    }
    func testLoggingOutDuringAnAddCannotLeaveAnOldNotification() async {
        let (service, center, _, _) = fixture()
        center.duringAdd = { service.bind(nil) }
        _ = await service.save(prefs)
        XCTAssertNil(service.scope)
        XCTAssertTrue(center.pending.isEmpty)
    }
    func testPreferencesPersistPerAccountAndOldScopeRoutesCannotOpen() async {
        let (service, center, _, defaults) = fixture()
        let saved = await service.save(prefs)
        XCTAssertTrue(saved)
        service.bind(nil)
        XCTAssertTrue(center.pending.isEmpty)
        let other = ReminderScope(accountID: UUID(), familyID: UUID(), pregnancyID: UUID())
        service.bind(other)
        XCTAssertFalse(service.preferences.enabled)
        service.receive(ReminderRoute(scope: scope, kind: .weekly))
        XCTAssertNil(service.pendingRoute)
        let restored = ReminderCoordinator(center: center, defaults: defaults, notificationCenter: NotificationCenter())
        restored.bind(scope)
        XCTAssertTrue(restored.preferences.enabled)
    }

    func testDisablingClearsOwnNotificationsAndDoesNotTouchAnotherModule() async {
        let (service, center, _, _) = fixture()
        center.pending["another.module"] = PlannedReminder(id: "another.module", fireAt: now,
            route: ReminderRoute(scope: scope, kind: .weekly))
        _ = await service.save(prefs)
        XCTAssertGreaterThan(center.pending.count, 1)
        var disabled = prefs; disabled.enabled = false
        _ = await service.save(disabled)
        XCTAssertEqual(Array(center.pending.keys), ["another.module"])
    }

    func testChangingFamilyClearsItsQueueEvenWhenTheAccountStaysTheSame() async {
        let (service, center, _, _) = fixture()
        _ = await service.save(prefs)
        XCTAssertFalse(center.pending.isEmpty)
        let family = ReminderScope(accountID: scope.accountID, familyID: UUID(), pregnancyID: UUID())
        service.bind(family)
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertTrue(service.preferences.enabled)
        service.receive(ReminderRoute(scope: scope, kind: .task, taskID: UUID()))
        XCTAssertNil(service.pendingRoute)
    }
    func testColdStartRouteSurvivesUntilItsMatchingScopeIsBound() {
        let (_, center, _, defaults) = fixture()
        let service = ReminderCoordinator(center: center, defaults: defaults, notificationCenter: NotificationCenter())
        let route = ReminderRoute(scope: scope, kind: .weekly)
        service.receive(route)
        service.bind(scope)
        XCTAssertEqual(service.pendingRoute?.route, route)
    }
    func testFailedRefreshCancelsOldRemindersInsteadOfKeepingOldDeadlines() async {
        let (service, center, repo, _) = fixture()
        let saved = await service.save(prefs)
        XCTAssertTrue(saved)
        repo.fail = true
        await service.refresh()
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertNotNil(service.errorMessage)
    }

    func testKeychainRoundTripForColdLaunchRequiresTheSignedSimulatorBuild() throws {
        let keychain = KeychainStore(service: "aim.reminders.keychain-test.\(UUID())")
        defer { keychain.delete("session") }
        try keychain.write("temporary-test-session", for: "session")
        XCTAssertEqual(keychain.read("session"), "temporary-test-session")
    }
}

@MainActor
private final class FakeReminderCenter: ReminderCenterProtocol {
    var permission = ReminderAuthorization.allowed
    var grant = true
    var pending: [String: PlannedReminder] = [:]
    var duringAdd: (() -> Void)?
    var duringPermission: (() async -> Void)?
    func authorization() async -> ReminderAuthorization { permission }
    func requestAuthorization() async throws -> Bool {
        await duringPermission?(); permission = grant ? .allowed : .denied; return grant
    }
    func pendingIDs() async -> [String] { Array(pending.keys) }
    func add(_ reminder: PlannedReminder) async throws {
        let hook = duringAdd; duringAdd = nil; hook?()
        pending[reminder.id] = reminder
    }
    func remove(_ identifiers: [String]) { for id in identifiers { pending.removeValue(forKey: id) } }
}

@MainActor
private final class ReminderRepository: BusinessRepositoryProtocol {
    var pregnancy: PregnancySummary
    var scope: ReminderScope
    var tasks: [TaskItem] = []
    var fail = false
    init(pregnancy: PregnancySummary, scope: ReminderScope) { self.pregnancy = pregnancy; self.scope = scope }
    func fetchPregnancy() async throws -> PregnancySummary? { if fail { throw APIError.invalidResponse }; return pregnancy }
    func fetchPlan() async throws -> PlanSnapshot { PlanSnapshot(id: UUID(), pregnancyID: scope.pregnancyID, version: 1, tasks: tasks) }
    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot { RecordSnapshot(records: []) }
    func fetchToday() async throws -> TodaySnapshot { throw APIError.invalidResponse }
    func fetchFamily() async throws -> FamilySnapshot { throw APIError.invalidResponse }
    func createPregnancy(dueDate: Date) async throws -> UUID { throw APIError.invalidResponse }
    func complete(task: TaskItem) async throws -> TaskItem { throw APIError.invalidResponse }
    func delay(task: TaskItem, until: Date) async throws -> TaskItem { throw APIError.invalidResponse }
    func schedule(task: TaskItem, at: Date) async throws -> TaskItem { throw APIError.invalidResponse }
    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem { throw APIError.invalidResponse }
    func invite(phone: String, role: FamilyRole) async throws { throw APIError.invalidResponse }
    func createRecord(draft: RecordDraft) async throws -> RecordItem { throw APIError.invalidResponse }
    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem { throw APIError.invalidResponse }
    func deleteRecord(recordID: UUID) async throws { throw APIError.invalidResponse }
    func createTaskFromRecord(record: RecordItem, title: String, description: String?, dueAt: Date?) async throws -> TaskItem { throw APIError.invalidResponse }
    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem { throw APIError.invalidResponse }
    func deleteTask(taskID: UUID) async throws { throw APIError.invalidResponse }
    func fetchSafetyRules() async throws -> [SafetyRule] { [] }
    func fetchContentCollection(_ name: String) async throws -> ContentCollection { ContentCollection(id: name, source: "test", sourceURL: "", items: []) }
    func renameFamily(to name: String) async throws {}
    func updateMyMembership(nickname: String?, role: FamilyRole?) async throws {}
    func requestAccountDeletion(password: String) async throws { throw APIError.notConfigured }
}
