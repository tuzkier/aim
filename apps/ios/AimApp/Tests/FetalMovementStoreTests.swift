import XCTest
@testable import AimApp

@MainActor
final class FetalMovementStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let accountA = UUID(), pregnancyA = UUID()
    private let accountB = UUID(), pregnancyB = UUID()

    override func setUp() {
        super.setUp()
        suiteName = "FetalMovementStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        notifications = NotificationCenter()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// 每个用例自己的通知中心：保存成功的广播不会惊动宿主 App 去真的刷新。
    private var notifications: NotificationCenter!

    private func makeStore(
        repository: FakeFetalRepository = FakeFetalRepository(), dedupe: TimeInterval = 3, bound: Bool = true
    ) -> FetalMovementStore {
        let store = FetalMovementStore(defaults: defaults, dedupeInterval: dedupe, notificationCenter: notifications)
        store.repository = repository
        store.clock = { [unowned self] in self.now }
        if bound { store.bind(accountID: accountA, pregnancyID: pregnancyA) }
        return store
    }

    func testAnActiveCountSurvivesARelaunch() {
        let first = makeStore()
        first.start()
        now += 40
        _ = first.tap()

        let relaunched = makeStore()
        XCTAssertEqual(relaunched.active?.count, 1, "App 被系统杀掉后要从断点继续")
        XCTAssertEqual(relaunched.active?.startedAt, first.active?.startedAt)
    }

    func testFinishingSavesTheRecordAndReloads() async {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository, dedupe: 0)
        store.start()
        for _ in 1...10 { now += 60; _ = store.tap() }

        let completion = await store.finish()

        XCTAssertEqual(completion?.result.outcome, .reached)
        XCTAssertEqual(completion?.saved, true)
        XCTAssertNil(store.active)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertEqual(repository.createdDrafts.first?.type, .fetalMovement)
        XCTAssertEqual(store.sessions.count, 1, "保存后重新拉取档案")
    }

    func testAFailedSaveKeepsTheResultForRetryAcrossRelaunch() async {
        let repository = FakeFetalRepository()
        repository.failCreates = true
        let store = makeStore(repository: repository)
        store.start()
        now += 30
        _ = store.tap()

        let completion = await store.finish()

        XCTAssertEqual(completion?.saved, false)
        XCTAssertEqual(store.unsaved.count, 1)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(makeStore(repository: repository).unsaved.count, 1, "没保存上的结果不能丢")

        repository.failCreates = false
        let saved = await store.saveUnsaved()
        XCTAssertTrue(saved)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(makeStore(repository: repository).unsaved.isEmpty)
    }

    func testBaselineIsCapturedBeforeTheNewSessionIsSaved() async {
        let repository = FakeFetalRepository()
        for seconds in [600, 620, 640] { repository.seed(seconds: seconds, at: now - 86_400) }
        let store = makeStore(repository: repository, dedupe: 0)
        await store.load()
        store.start()
        for _ in 1...10 { now += 200; _ = store.tap() }

        let completion = await store.finish()

        XCTAssertEqual(completion?.baselineSeconds, 620)
        XCTAssertEqual(completion?.isSlow, true, "2000 秒 > 620 × 2 且 > 30 分钟")
    }

    func testDiscardingAnEmptyCountLeavesNothingBehind() {
        let store = makeStore()
        store.start()
        store.discardActive()
        XCTAssertNil(store.active)
        XCTAssertNil(makeStore().active)
    }

    /// 一次都没数就点了「胎动明显少了？」：这句主诉本身要留档，记一条 0 次的未数完。
    func testAbandoningForSafetyRecordsAnEmptyCountAsReportedLess() async throws {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository)
        store.start()
        now += 75.8

        let completion = await store.abandonForSafety()

        XCTAssertEqual(completion?.result.outcome, .stopped)
        XCTAssertEqual(completion?.result.count, 0)
        XCTAssertEqual(completion?.result.durationSeconds, 75)
        XCTAssertEqual(completion?.result.reportedLess, true)
        XCTAssertEqual(completion?.saved, true)
        XCTAssertNil(store.active)
        XCTAssertNil(makeStore(repository: repository).active, "不留断点")
        let draft = try XCTUnwrap(repository.createdDrafts.first)
        guard case let .fetalMovement(data) = draft.structuredData else { return XCTFail("应当是胎动记录") }
        XCTAssertTrue(data.reportedLess)
        XCTAssertEqual(data.taps, [])
    }

    /// 0 次时用时取已过去的秒数，但不超过后端允许的 3 小时。
    func testAnEmptyReportedLessCountIsCappedAtThreeHours() async {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository)
        store.start()
        now += 5 * 3_600

        let completion = await store.abandonForSafety()

        XCTAssertEqual(completion?.result.outcome, .stopped)
        XCTAssertEqual(completion?.result.durationSeconds, 10_800)
        XCTAssertEqual(repository.createdDrafts.count, 1)
    }

    func testAbandoningForSafetyRecordsAStartedCountAsStopped() async {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository)
        store.start()
        now += 60; _ = store.tap()
        now += 60; _ = store.tap()
        now += 30

        let completion = await store.abandonForSafety()

        XCTAssertEqual(completion?.result.outcome, .stopped)
        XCTAssertEqual(completion?.result.count, 2)
        XCTAssertEqual(completion?.result.reportedLess, true, "计数中报告过胎动少了")
        XCTAssertEqual(completion?.saved, true)
        XCTAssertNil(store.active)
        XCTAssertNil(makeStore(repository: repository).active, "不能留下一个下次打开会接着数的断点")
        XCTAssertEqual(repository.createdDrafts.count, 1)
    }

    func testAbandoningForSafetyAfterTwoHoursRecordsUnder() async {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository)
        store.start()
        now += 60; _ = store.tap()
        now += FetalMovementCounter.window

        let completion = await store.abandonForSafety()

        XCTAssertEqual(completion?.result.outcome, .under)
        XCTAssertEqual(repository.createdDrafts.count, 1)
    }

    func testAbandoningForSafetyBeforeBindingDoesNothing() async {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository, bound: false)
        store.start()

        let completion = await store.abandonForSafety()

        XCTAssertNil(completion)
        XCTAssertTrue(repository.createdDrafts.isEmpty)
    }

    // MARK: - 被系统杀掉后过期的断点

    /// 计数页没开着时到了 2 小时：孕妈并没有在数，不能报「不足 10 次」，记为未数完。
    func testSettlingAnExpiredCountSavesItAsStoppedAtTheLastTap() async throws {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository)
        store.start()
        now += 100.7; _ = store.tap()
        now += 300; _ = store.tap()
        let relaunched = makeStore(repository: repository)
        now += 3 * 3_600

        await relaunched.settleExpiredActive()

        XCTAssertNil(relaunched.active)
        XCTAssertNil(makeStore(repository: repository).active, "断点已清掉并落盘")
        XCTAssertTrue(relaunched.unsaved.isEmpty)
        let draft = try XCTUnwrap(repository.createdDrafts.first)
        guard case let .fetalMovement(data) = draft.structuredData else { return XCTFail("应当是胎动记录") }
        XCTAssertEqual(data.outcome, .stopped)
        XCTAssertEqual(data.count, 2)
        XCTAssertEqual(data.durationSeconds, 400, "用时取最后一次点按的秒数")
        XCTAssertEqual(data.taps, [100, 400])
        XCTAssertFalse(data.reportedLess)
    }

    func testSettlingAnExpiredEmptyCountDiscardsIt() async {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository)
        store.start()
        now += 3 * 3_600

        await store.settleExpiredActive()

        XCTAssertNil(store.active)
        XCTAssertNil(makeStore(repository: repository).active)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertTrue(repository.createdDrafts.isEmpty, "一次都没数，不写档案")
    }

    func testSettlingACountThatHasNotExpiredDoesNothing() async {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository)
        store.start()
        now += 60; _ = store.tap()
        now += 3_600

        await store.settleExpiredActive()

        XCTAssertEqual(store.active?.count, 1)
        XCTAssertEqual(makeStore(repository: repository).active?.count, 1)
        XCTAssertTrue(repository.createdDrafts.isEmpty)
    }

    /// 冷启动慢、孕妈已经点「继续」打开计数页：这时满 2 小时是真实的「不足 10 次」，
    /// 由计数页自己结束并弹安全页，后台的收尾不能抢先记成未数完。
    func testSettlingLeavesAnExpiredCountAloneWhileTheCounterIsShowing() async {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository)
        store.start()
        now += 60; _ = store.tap()
        store.beginCounterPresentation()
        now += FetalMovementCounter.window + 1

        XCTAssertFalse(store.queueExpiredActive())
        await store.settleExpiredActive()

        XCTAssertEqual(store.active?.count, 1, "计数页开着，断点留给它自己结束")
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertTrue(repository.createdDrafts.isEmpty)
    }

    func testSettlingResumesOnceTheCounterCloses() async throws {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository)
        store.start()
        now += 60; _ = store.tap()
        // 嵌套或重复出现：每次出现各自配一次关闭，全部关掉才恢复收尾。
        store.beginCounterPresentation()
        store.beginCounterPresentation()
        now += FetalMovementCounter.window + 1
        store.endCounterPresentation()
        await store.settleExpiredActive()
        XCTAssertEqual(store.active?.count, 1, "还有一个计数页开着")

        store.endCounterPresentation()
        await store.settleExpiredActive()

        XCTAssertNil(store.active)
        let draft = try XCTUnwrap(repository.createdDrafts.first)
        guard case let .fetalMovement(data) = draft.structuredData else { return XCTFail("应当是胎动记录") }
        XCTAssertEqual(data.outcome, .stopped)
    }

    /// 标记残留（计数页被「问问 AIM」盖住时整条呈现链被拆掉）时，下次打开计数页
    /// 仍要先把过期断点记为未数完，不能沿用它、到点误报成「不足 10 次」。
    func testCounterAppearSettlesAnExpiredCountEvenIfAPresentationLingers() {
        let store = makeStore()
        store.start()
        now += 60; _ = store.tap()
        store.beginCounterPresentation()
        now += FetalMovementCounter.window + 1

        XCTAssertTrue(store.queueExpiredActiveBeforeCounting())

        XCTAssertNil(store.active)
        XCTAssertEqual(store.unsaved.map(\.outcome), [.stopped])
        XCTAssertEqual(store.unsaved.first?.count, 1)
    }

    func testUnbindingClearsLingeringCounterPresentations() {
        let store = makeStore()
        store.beginCounterPresentation()
        store.unbind()
        XCTAssertFalse(store.isCounterPresented)
    }

    func testSwitchingScopeClearsLingeringCounterPresentations() {
        let store = makeStore()
        store.beginCounterPresentation()
        store.bind(accountID: accountA, pregnancyID: pregnancyA)
        XCTAssertTrue(store.isCounterPresented, "同一作用域重复绑定不算换家")
        store.bind(accountID: accountB, pregnancyID: pregnancyB)
        XCTAssertFalse(store.isCounterPresented)
    }

    /// 多关一次不会把计数减成负数，否则下次打开计数页时标记就失灵了。
    func testClosingMoreThanOpenedDoesNotGoNegative() {
        let store = makeStore()
        store.endCounterPresentation()
        store.beginCounterPresentation()
        XCTAssertTrue(store.isCounterPresented)
        store.endCounterPresentation()
        XCTAssertFalse(store.isCounterPresented)
    }

    /// 首页卡与胎动页据此显示「继续」：过期的不算，等收尾。
    func testOnlyAnUnexpiredCountCanBeResumed() {
        let store = makeStore()
        XCTAssertNil(store.unfinishedActive)
        store.start()
        now += 60; _ = store.tap()
        XCTAssertEqual(store.unfinishedActive?.count, 1)
        now += FetalMovementCounter.window
        XCTAssertNil(store.unfinishedActive)
    }

    // MARK: - 当场判断「慢一倍多」

    /// 历史已在手：结束那一刻就能判断，不等保存（这里保存一直失败）。
    func testSlowNoticeIsAvailableBeforeSavingWhenHistoryIsLoaded() async throws {
        let repository = FakeFetalRepository()
        for seconds in [600, 620, 640] { repository.seed(seconds: seconds, at: now - 86_400) }
        let store = makeStore(repository: repository, dedupe: 0)
        await store.load()
        repository.failCreates = true
        store.start()
        for _ in 1...10 { now += 200; _ = store.tap() }
        let local = try XCTUnwrap(store.active).result(at: now)

        let notice = store.slowNoticeBeforeSaving(local)

        XCTAssertEqual(notice, FetalMovementSlowNotice(durationSeconds: 2_000, baselineSeconds: 620))
        let completion = await store.finish()
        XCTAssertEqual(completion?.saved, false)
        XCTAssertEqual(completion?.slowNotice, notice, "保存回来的判断与当场的一致")
    }

    /// 历史还没拉回来：当场没法判断，交给 finish() 拉到历史后补上。
    func testSlowNoticeWaitsForTheCompletionWhenHistoryIsEmpty() throws {
        let repository = FakeFetalRepository()
        for seconds in [600, 620, 640] { repository.seed(seconds: seconds, at: now - 86_400) }
        let store = makeStore(repository: repository, dedupe: 0)
        store.start()
        for _ in 1...10 { now += 200; _ = store.tap() }

        XCTAssertNil(store.slowNoticeBeforeSaving(try XCTUnwrap(store.active).result(at: now)))
    }

    func testANormalPaceHasNoSlowNotice() async throws {
        let repository = FakeFetalRepository()
        for seconds in [600, 620, 640] { repository.seed(seconds: seconds, at: now - 86_400) }
        let store = makeStore(repository: repository, dedupe: 0)
        await store.load()
        store.start()
        for _ in 1...10 { now += 60; _ = store.tap() }

        XCTAssertNil(store.slowNoticeBeforeSaving(try XCTUnwrap(store.active).result(at: now)))
    }

    // MARK: - 保存后通知其他页面

    func testASuccessfulSaveTellsOtherPagesThatRecordsChanged() async {
        final class Received: @unchecked Sendable { var kinds: [[String]] = [] }
        let received = Received()
        // 通知在发送方所在线程同步投递，这里就是主线程。
        let token = notifications.addObserver(forName: .aimDataChanged, object: nil, queue: nil) { note in
            received.kinds.append(note.userInfo?["kinds"] as? [String] ?? [])
        }
        defer { notifications.removeObserver(token) }
        let repository = FakeFetalRepository()
        repository.failCreates = true
        let store = makeStore(repository: repository)
        store.start(); now += 30; _ = store.tap()

        _ = await store.finish()
        XCTAssertTrue(received.kinds.isEmpty, "没保存上不通知")

        repository.failCreates = false
        await store.saveUnsaved()
        XCTAssertEqual(received.kinds, [["record"]])
    }

    /// 上一次没保存上、这一次也没保存上：两条都要留着，不能后一条把前一条覆盖掉。
    func testTwoFailedSavesAreBothQueuedAndRetriedInOrder() async {
        let repository = FakeFetalRepository()
        repository.failCreates = true
        let store = makeStore(repository: repository)
        store.start(); now += 30; _ = store.tap()
        let first = await store.finish()
        now += 3_600
        store.start(); now += 30; _ = store.tap()
        let second = await store.finish()

        XCTAssertEqual(first?.saved, false)
        XCTAssertEqual(second?.saved, false)
        XCTAssertEqual(store.unsaved.count, 2)
        XCTAssertEqual(makeStore(repository: repository).unsaved.count, 2, "重启后队列还在")

        repository.failCreates = false
        let saved = await store.saveUnsaved()

        XCTAssertTrue(saved)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertEqual(repository.createdDrafts.map(\.occurredAt),
                       [first?.result.startedAt, second?.result.startedAt].compactMap { $0 },
                       "旧的先保存")
        XCTAssertTrue(makeStore(repository: repository).unsaved.isEmpty, "重启后也为空")
    }

    /// 换账号或家庭后各自独立；切回来还能接着数。
    func testEachAccountAndPregnancyKeepsItsOwnCount() {
        let store = makeStore()
        store.start()
        now += 40
        _ = store.tap()

        store.bind(accountID: accountB, pregnancyID: pregnancyB)
        XCTAssertNil(store.active)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertTrue(store.sessions.isEmpty)

        store.bind(accountID: accountA, pregnancyID: pregnancyA)
        XCTAssertEqual(store.active?.count, 1)
    }

    /// 不知道是哪一家时，什么都不能记，免得存错地方。
    func testNothingHappensBeforeBinding() async {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository, bound: false)

        store.start()
        XCTAssertNil(store.active)
        XCTAssertEqual(store.tap(), .ignored)
        let completion = await store.finish()
        XCTAssertNil(completion)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertTrue(repository.createdDrafts.isEmpty)
    }

    /// 保存还没回来时再点「重试」，不能把同一条存两遍。
    func testSavingAgainWhileASaveIsInFlightDoesNothing() async {
        let repository = FakeFetalRepository()
        let gate = Gate()
        repository.gate = gate
        let store = makeStore(repository: repository)
        store.start()
        now += 30
        _ = store.tap()

        let finishing = Task { await store.finish() }
        while await gate.calls == 0 { await Task.yield() }

        // 第二次调用放进独立任务：缺了防重入时它会卡在同一道闸门上，放行后多发一次请求，
        // 测试以失败而不是挂起的方式暴露问题。
        let retrying = Task { await store.saveUnsaved() }
        for _ in 0..<10 { await Task.yield() }

        await gate.release()
        let second = await retrying.value
        let completion = await finishing.value
        XCTAssertFalse(second, "保存进行中，第二次调用直接返回")

        XCTAssertEqual(completion?.saved, true)
        let calls = await gate.calls
        XCTAssertEqual(calls, 1, "只发出一次保存请求")
        XCTAssertEqual(repository.createdDrafts.count, 1)
        XCTAssertTrue(store.unsaved.isEmpty)
    }

    /// 打开计数页就直接开始数、历史还没拉回来时，「和平时比」不能静默缺失。
    func testBaselineIsAvailableEvenIfHistoryWasNotLoaded() async {
        let repository = FakeFetalRepository()
        for seconds in [600, 620, 640] { repository.seed(seconds: seconds, at: now - 86_400) }
        let store = makeStore(repository: repository, dedupe: 0)
        store.start()
        for _ in 1...10 { now += 200; _ = store.tap() }

        let completion = await store.finish()

        XCTAssertEqual(completion?.baselineSeconds, 620)
        XCTAssertEqual(completion?.isSlow, true)
    }

    /// 给作用域 B 留一条没保存上的结果。
    private func queueUnsavedResultForB() async {
        let offline = FakeFetalRepository()
        offline.failCreates = true
        let storeB = makeStore(repository: offline, bound: false)
        storeB.bind(accountID: accountB, pregnancyID: pregnancyB)
        storeB.start(); now += 30; _ = storeB.tap()
        _ = await storeB.finish()
        XCTAssertEqual(storeB.unsaved.count, 1)
        now += 3_600
    }

    /// 保存请求在路上时换了一家：那条要从原来那家的队列里移掉，
    /// 新的一家的队列不受影响，也不能把原来那家的历史拉进来。
    func testSwitchingScopeWhileSavingKeepsEachQueueSeparate() async {
        await queueUnsavedResultForB()

        let repository = FakeFetalRepository()
        let gate = Gate()
        repository.gate = gate
        let store = makeStore(repository: repository)
        store.start(); now += 30; _ = store.tap()

        let finishing = Task { await store.finish() }
        while await gate.calls == 0 { await Task.yield() }
        store.bind(accountID: accountB, pregnancyID: pregnancyB)
        await gate.release()
        let completion = await finishing.value

        XCTAssertEqual(completion?.saved, true, "请求确实存上了")
        XCTAssertNil(completion?.baselineSeconds)
        XCTAssertTrue(makeStore().unsaved.isEmpty, "A 落盘的队列移除了那一条")
        XCTAssertEqual(store.unsaved.count, 1, "B 的队列不受影响")
        let calls = await gate.calls
        XCTAssertEqual(calls, 1, "没有替 B 发保存请求")
        XCTAssertTrue(store.sessions.isEmpty, "A 的历史不能写进 B")
    }

    /// 结束后还在拉历史时换了一家：不能误报已保存，也不能拿 B 的历史当平时、替 B 保存。
    func testSwitchingScopeWhileFinishingDoesNotReportSaved() async {
        await queueUnsavedResultForB()
        let repository = FakeFetalRepository()
        for seconds in [600, 620, 640] { repository.seed(seconds: seconds, at: now - 86_400) }
        let fetchGate = Gate()
        repository.fetchGate = fetchGate
        let store = makeStore(repository: repository, dedupe: 0)
        store.start()
        for _ in 1...10 { now += 200; _ = store.tap() }

        let finishing = Task { await store.finish() }
        while await fetchGate.calls == 0 { await Task.yield() }
        store.bind(accountID: accountB, pregnancyID: pregnancyB)
        await fetchGate.release()
        let completion = await finishing.value

        XCTAssertEqual(completion?.saved, false)
        XCTAssertNil(completion?.baselineSeconds)
        XCTAssertTrue(repository.createdDrafts.isEmpty, "没有以 B 的身份保存")
        XCTAssertEqual(store.unsaved.count, 1, "B 只有它自己原来那一条")
        XCTAssertNotEqual(store.unsaved.first, completion?.result, "结果没有跑进 B 的队列")
        XCTAssertEqual(makeStore(repository: repository).unsaved.count, 1, "结果留在 A 的队列里，切回来可重试")
    }

    /// 退出登录或切到没有孕期的家庭后，下一位用户看不到也写不了上一位的计数。
    func testUnbindingHidesTheCountUntilBoundAgain() async {
        let repository = FakeFetalRepository()
        repository.failCreates = true
        let store = makeStore(repository: repository)
        store.start(); now += 30; _ = store.tap()
        _ = await store.finish()
        now += 3_600
        store.start(); now += 30; _ = store.tap()

        store.unbind()

        XCTAssertNil(store.active)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertNil(store.errorMessage)
        store.start()
        XCTAssertNil(store.active, "解绑后不能开始计数")
        XCTAssertEqual(store.tap(), .ignored)

        store.bind(accountID: accountA, pregnancyID: pregnancyA)
        XCTAssertEqual(store.active?.count, 1, "绑回来能找回断点")
        XCTAssertEqual(store.unsaved.count, 1, "绑回来能找回未保存结果")
    }

    /// 解绑后旧仓库还带着上一家的身份：不能再拿它把上一家的历史读回来。
    func testLoadingAfterUnbindDoesNotFetchTheOldFamily() async {
        let repository = FakeFetalRepository()
        repository.seed(seconds: 600, at: now - 86_400)
        let store = makeStore(repository: repository)

        store.unbind()
        XCTAssertNil(store.repository, "解绑时一并丢掉旧仓库")
        await store.load()
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertEqual(repository.fetchCalls, 0, "解绑后不发拉取请求")

        // 调用方先设了仓库、还没绑定：仍然不知道是哪一家，照样不拉。
        store.repository = repository
        await store.load()
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertEqual(repository.fetchCalls, 0)
    }

    /// 解绑后、或者已经换到另一家时，不能删掉上一家的记录。
    func testDeletingAfterUnbindDoesNotTouchTheOldFamily() async throws {
        let repository = FakeFetalRepository()
        repository.seed(seconds: 600, at: now - 86_400)
        let store = makeStore(repository: repository)
        await store.load()
        let old = try XCTUnwrap(store.sessions.first)

        store.unbind()
        await store.delete(old)
        XCTAssertTrue(repository.deletedIDs.isEmpty, "解绑后不发删除请求")

        store.repository = repository
        await store.delete(old)
        XCTAssertTrue(repository.deletedIDs.isEmpty, "未绑定时即使有仓库也不删")

        store.bind(accountID: accountB, pregnancyID: pregnancyB)
        await store.delete(old)
        XCTAssertTrue(repository.deletedIDs.isEmpty, "不在当前这一家列表里的记录不删")
        XCTAssertEqual(repository.records.count, 1)
    }

    /// 保存成功后正在刷新历史时又结束了一次计数：这一次必须立刻保存，不能被当成重入挡掉。
    func testFinishingWhileTheSaveRefreshIsInFlightStillSaves() async {
        let repository = FakeFetalRepository()
        repository.seed(seconds: 600, at: now - 86_400)
        let store = makeStore(repository: repository)
        // 先拉过历史，第二次 finish 就不会自己去拉，直接进入保存。
        await store.load()
        let fetchGate = Gate()
        repository.fetchGate = fetchGate

        store.start(); now += 30; _ = store.tap()
        let firstFinishing = Task { await store.finish() }
        // 第一条已保存，卡在保存后的那次刷新上。
        while await fetchGate.calls == 0 { await Task.yield() }
        XCTAssertEqual(repository.createdDrafts.count, 1)

        now += 3_600
        store.start(); now += 30; _ = store.tap()
        let secondFinishing = Task { await store.finish() }
        // 修好时第二条保存后也卡在刷新上（calls == 2）；没修好时它会直接返回 saved == false。
        // 有上限地等，避免在没修好时挂起。
        for _ in 0..<1_000 {
            if await fetchGate.calls >= 2 { break }
            await Task.yield()
        }

        await fetchGate.release()
        let first = await firstFinishing.value
        let second = await secondFinishing.value

        XCTAssertEqual(first?.saved, true)
        XCTAssertEqual(second?.saved, true, "刷新期间结束的计数要立刻保存")
        XCTAssertEqual(repository.createdDrafts.count, 2, "一共保存了 2 条")
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertEqual(store.sessions.count, 3)
    }

    /// 两次拉历史并发、先发的后回来：旧响应不能盖掉新结果。
    func testAnOlderReloadThatReturnsLateDoesNotOverwriteANewerOne() async {
        let repository = FakeFetalRepository()
        repository.seed(seconds: 600, at: now - 86_400)
        let fetchGate = Gate()
        repository.fetchGate = fetchGate
        let store = makeStore(repository: repository)

        let older = Task { await store.load() }
        while await fetchGate.calls == 0 { await Task.yield() }

        // 第二次请求不卡，并且看得到新增的那条。
        repository.fetchGate = nil
        repository.seed(seconds: 620, at: now - 3_600)
        await store.load()
        XCTAssertEqual(store.sessions.count, 2)

        await fetchGate.release()
        await older.value
        XCTAssertEqual(store.sessions.count, 2, "先发的请求后回来，只看到 1 条，不能采用")
    }
}

/// 让替身的请求停在半路，直到测试放行；同时数一共被调了几次。
private actor Gate {
    private(set) var calls = 0
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        calls += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// 只实现胎动用到的三个接口；其余照抄 LibraryStoreTests 的 FakeLibraryRepository，
/// 一律 `throw APIError.notConfigured`（有默认实现的不必写）。
private final class FakeFetalRepository: BusinessRepositoryProtocol, @unchecked Sendable {
    var records: [RecordItem] = []
    var createdDrafts: [RecordDraft] = []
    var failCreates = false
    /// 卡住 createRecord。
    var gate: Gate?
    /// 卡住 fetchRecords。
    var fetchGate: Gate?
    private(set) var fetchCalls = 0
    private(set) var deletedIDs: [UUID] = []

    func seed(seconds: Int, at date: Date) {
        records.append(item(FetalMovementResult(
            startedAt: date, durationSeconds: seconds, count: 10, outcome: .reached,
            taps: Array(repeating: 0, count: 10)).draft))
    }

    private func item(_ draft: RecordDraft) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: draft.type, occurredAt: draft.occurredAt, visibility: draft.visibility,
            title: draft.title, content: draft.content, structuredData: draft.structuredData,
            attachmentRefs: [], createdAt: .now, updatedAt: .now)
    }

    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot {
        fetchCalls += 1
        // 先取快照再等闸门：卡在半路的请求返回的是发出那一刻的数据，才能构造出乱序的旧响应。
        let snapshot = RecordSnapshot(records: records.filter { type == nil || $0.type == type })
        if let fetchGate { await fetchGate.pass() }
        return snapshot
    }

    func createRecord(draft: RecordDraft) async throws -> RecordItem {
        if let gate { await gate.pass() }
        if failCreates { throw APIError.invalidResponse }
        createdDrafts.append(draft)
        let created = item(draft)
        records.append(created)
        return created
    }

    func deleteRecord(recordID: UUID) async throws {
        deletedIDs.append(recordID)
        records.removeAll { $0.id == recordID }
    }

    // 以下照抄 Tests/LibraryStoreTests.swift 里 FakeLibraryRepository 的其余必需方法，
    // 全部 throw APIError.notConfigured（返回 Void 的写成空实现）。
    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func fetchSafetyRules() async throws -> [SafetyRule] { throw APIError.notConfigured }
    func fetchContentCollection(_ name: String) async throws -> ContentCollection { throw APIError.notConfigured }
    func fetchToday() async throws -> TodaySnapshot { throw APIError.notConfigured }
    func fetchPlan() async throws -> PlanSnapshot { throw APIError.notConfigured }
    func fetchFamily() async throws -> FamilySnapshot { throw APIError.notConfigured }
    func createPregnancy(dueDate: Date) async throws -> UUID { throw APIError.notConfigured }
    func deleteTask(taskID: UUID) async throws {}
    func createTaskFromRecord(record: RecordItem, title: String, description: String?, dueAt: Date?) async throws -> TaskItem { throw APIError.notConfigured }
    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem { throw APIError.notConfigured }
    func complete(task: TaskItem) async throws -> TaskItem { throw APIError.notConfigured }
    func delay(task: TaskItem, until: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func schedule(task: TaskItem, at: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem { throw APIError.notConfigured }
    func invite(phone: String, role: FamilyRole) async throws { throw APIError.notConfigured }
    func renameFamily(to name: String) async throws {}
    func updateMyMembership(nickname: String?, role: FamilyRole?) async throws {}
    func requestAccountDeletion(password: String) async throws { throw APIError.notConfigured }
}
