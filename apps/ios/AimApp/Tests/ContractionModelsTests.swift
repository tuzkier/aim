import XCTest
@testable import AimApp

final class ContractionModelsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // 与 contracts/fixtures/contraction-summary-vectors.json 保持一致，改那边要同步改这里。
    private let vectorsJSON = #"""
    {
      "_comment": "宫缩档位计算的共享测试向量。API（tests/domain/records/test_contraction.py）直接读取；iOS（Tests/ContractionModelsTests.swift）内嵌同一份拷贝，改这里要同步改那边。",
      "vectors": [
        {
          "name": "只有一次",
          "contractions": [[0, 60]],
          "expected": {"count": 1, "last_hour_count": 1, "avg_interval_seconds": null, "avg_duration_seconds": 60, "pattern": "early"}
        },
        {
          "name": "十分钟一次，还早",
          "contractions": [[0, 40], [600, 40], [1200, 40], [1800, 40]],
          "expected": {"count": 4, "last_hour_count": 4, "avg_interval_seconds": 600, "avg_duration_seconds": 40, "pattern": "early"}
        },
        {
          "name": "最近半小时 4 次、7 分钟一次，接近",
          "contractions": [[0, 45], [420, 45], [840, 45], [1260, 45]],
          "expected": {"count": 4, "last_hour_count": 4, "avg_interval_seconds": 420, "avg_duration_seconds": 45, "pattern": "approaching"}
        },
        {
          "name": "最近半小时 4 次、但 7 分 1 秒一次，差一点",
          "contractions": [[0, 45], [421, 45], [842, 45], [1263, 45]],
          "expected": {"count": 4, "last_hour_count": 4, "avg_interval_seconds": 421, "avg_duration_seconds": 45, "pattern": "early"}
        },
        {
          "name": "满一小时、5 分钟一次、每次 50 秒：符合 5-1-1",
          "contractions": [[0, 50], [300, 50], [600, 50], [900, 50], [1200, 50], [1500, 50], [1800, 50], [2100, 50], [2400, 50], [2700, 50], [3000, 50], [3300, 50]],
          "expected": {"count": 12, "last_hour_count": 12, "avg_interval_seconds": 300, "avg_duration_seconds": 50, "pattern": "go"}
        },
        {
          "name": "跨度只有 54 分 59 秒：还不算满一小时",
          "contractions": [[0, 50], [299, 50], [599, 50], [899, 50], [1199, 50], [1499, 50], [1799, 50], [2099, 50], [2399, 50], [2699, 50], [2999, 50], [3299, 50]],
          "expected": {"count": 12, "last_hour_count": 12, "avg_interval_seconds": 300, "avg_duration_seconds": 50, "pattern": "approaching"}
        },
        {
          "name": "满一小时但平均持续 49 秒",
          "contractions": [[0, 49], [300, 49], [600, 49], [900, 49], [1200, 49], [1500, 49], [1800, 49], [2100, 49], [2400, 49], [2700, 49], [3000, 49], [3300, 49]],
          "expected": {"count": 12, "last_hour_count": 12, "avg_interval_seconds": 300, "avg_duration_seconds": 49, "pattern": "approaching"}
        },
        {
          "name": "满一小时但 5 分 30 秒一次",
          "contractions": [[0, 60], [330, 60], [660, 60], [990, 60], [1320, 60], [1650, 60], [1980, 60], [2310, 60], [2640, 60], [2970, 60], [3300, 60]],
          "expected": {"count": 11, "last_hour_count": 11, "avg_interval_seconds": 330, "avg_duration_seconds": 60, "pattern": "approaching"}
        },
        {
          "name": "一小时以前的宫缩不进窗口",
          "contractions": [[0, 30], [1000, 30], [5000, 60], [5300, 60], [5600, 60], [5900, 60]],
          "expected": {"count": 6, "last_hour_count": 4, "avg_interval_seconds": 300, "avg_duration_seconds": 60, "pattern": "approaching"}
        },
        {
          "name": "平均值四舍五入",
          "contractions": [[0, 50], [301, 51], [602, 50]],
          "expected": {"count": 3, "last_hour_count": 3, "avg_interval_seconds": 301, "avg_duration_seconds": 50, "pattern": "early"}
        }
      ]
    }
    """#

    private struct VectorFile: Decodable {
        struct Vector: Decodable {
            let name: String
            let contractions: [[Int]]
            let expected: Expected
        }
        struct Expected: Decodable {
            let count: Int
            let last_hour_count: Int
            let avg_interval_seconds: Int?
            let avg_duration_seconds: Int
            let pattern: String
        }
        let vectors: [Vector]
    }

    func testSummaryMatchesSharedVectors() throws {
        let file = try JSONDecoder().decode(VectorFile.self, from: Data(vectorsJSON.utf8))
        XCTAssertFalse(file.vectors.isEmpty)
        for vector in file.vectors {
            let entries = vector.contractions.map { ContractionEntry(start: $0[0], duration: $0[1]) }
            let summary = ContractionMath.summary(entries)
            XCTAssertEqual(summary.count, vector.expected.count, vector.name)
            XCTAssertEqual(summary.lastHourCount, vector.expected.last_hour_count, vector.name)
            XCTAssertEqual(summary.avgIntervalSeconds, vector.expected.avg_interval_seconds, vector.name)
            XCTAssertEqual(summary.avgDurationSeconds, vector.expected.avg_duration_seconds, vector.name)
            XCTAssertEqual(summary.pattern.rawValue, vector.expected.pattern, vector.name)
        }
    }

    // MARK: - 计时器

    func testToggleBeginsAndEndsAContraction() {
        var timer = ContractionTimer()
        XCTAssertEqual(timer.toggle(at: t0), .began)
        XCTAssertTrue(timer.isContracting)
        XCTAssertEqual(timer.toggle(at: t0 + 62.7), .ended)
        XCTAssertFalse(timer.isContracting)
        XCTAssertEqual(timer.entries(), [ContractionEntry(start: 0, duration: 62)])
    }

    func testEndingWithinOneSecondIsTreatedAsAMistap() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        XCTAssertEqual(timer.toggle(at: t0 + 0.5), .ignored)
        XCTAssertTrue(timer.spans.isEmpty, "不到 1 秒就结束是误触，这一次整个取消")
    }

    func testBeginningRightAfterTheLastEndIsIgnored() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        _ = timer.toggle(at: t0 + 60)
        XCTAssertEqual(timer.toggle(at: t0 + 60.4), .ignored)
        XCTAssertEqual(timer.toggle(at: t0 + 300), .began)
    }

    func testEntriesAreOffsetsFromTheFirstStartAndNeverOverlap() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0 + 0.9)
        _ = timer.toggle(at: t0 + 60.2)
        _ = timer.toggle(at: t0 + 61.3)
        _ = timer.toggle(at: t0 + 120.8)
        let entries = timer.entries()
        XCTAssertEqual(entries.first?.start, 0)
        for (previous, next) in zip(entries, entries.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next.start, previous.start + previous.duration)
        }
    }

    func testEntriesSkipTheRunningContraction() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        _ = timer.toggle(at: t0 + 60)
        _ = timer.toggle(at: t0 + 300)
        XCTAssertEqual(timer.entries().count, 1)
    }

    func testRemoveLastCancelsRunningOrDeletesTheLastCompleted() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        _ = timer.toggle(at: t0 + 60)
        _ = timer.toggle(at: t0 + 300)
        timer.removeLast()
        XCTAssertFalse(timer.isContracting)
        XCTAssertEqual(timer.spans.count, 1)
        timer.removeLast()
        XCTAssertTrue(timer.spans.isEmpty)
    }

    func testCapRunningTruncatesAfterTenMinutes() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        timer.capRunning(at: t0 + 300)
        XCTAssertTrue(timer.isContracting, "不到 10 分钟不截断")
        timer.capRunning(at: t0 + 3600)
        XCTAssertFalse(timer.isContracting)
        XCTAssertEqual(timer.entries(), [ContractionEntry(start: 0, duration: 600)])
    }

    func testStaleAfterSixHoursSinceTheLastEnd() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        _ = timer.toggle(at: t0 + 60)
        XCTAssertFalse(timer.isStale(at: t0 + 60 + 21_600))
        XCTAssertTrue(timer.isStale(at: t0 + 60 + 21_601))
    }

    func testTimerSurvivesEncoding() throws {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        let decoded = try JSONDecoder().decode(ContractionTimer.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(decoded, timer)
    }

    // MARK: - 实时档位

    /// 每 interval 秒一次、每次 duration 秒，共 count 次，从 t0 开始。
    private func timer(count: Int, interval: TimeInterval, duration: TimeInterval) -> ContractionTimer {
        var timer = ContractionTimer()
        for i in 0..<count {
            let start = t0 + Double(i) * interval
            _ = timer.toggle(at: start)
            _ = timer.toggle(at: start + duration)
        }
        return timer
    }

    func testLiveStatusMatchesTheStoredSummaryRightAfterTheLastContraction() {
        let timer = timer(count: 12, interval: 300, duration: 55)
        let status = ContractionMath.status(timer, at: t0 + 3300 + 55, weeks: 39)
        XCTAssertEqual(status.stage, .go)
        XCTAssertEqual(status.summary, ContractionMath.summary(timer.entries()))
    }

    func testLongQuietFallsBackToEarly() {
        let timer = timer(count: 12, interval: 300, duration: 55)
        let lastEnd = t0 + 3300 + 55
        XCTAssertEqual(ContractionMath.status(timer, at: lastEnd + 1200, weeks: 39).stage, .go)
        let quiet = ContractionMath.status(timer, at: lastEnd + 1201, weeks: 39)
        XCTAssertEqual(quiet.stage, .early)
        XCTAssertEqual(quiet.quietMinutes, 20)
    }

    func testPretermAlertForFourInTwentyMinutes() {
        let timer = timer(count: 4, interval: 300, duration: 40)
        let now = t0 + 900 + 40
        XCTAssertEqual(ContractionMath.status(timer, at: now, weeks: 35).stage, .pretermAlert)
        XCTAssertNotEqual(ContractionMath.status(timer, at: now, weeks: 37).stage, .pretermAlert)
        XCTAssertNotEqual(ContractionMath.status(timer, at: now, weeks: nil).stage, .pretermAlert,
                          "不知道孕周时不猜")
    }

    func testPretermAlertForEightInAnHour() {
        let timer = timer(count: 8, interval: 480, duration: 40)
        let now = t0 + 7 * 480 + 40
        XCTAssertEqual(ContractionMath.status(timer, at: now, weeks: 33).stage, .pretermAlert)
    }

    func testRunningContractionReportsSecondsAndLongRunning() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        XCTAssertEqual(ContractionMath.status(timer, at: t0 + 30, weeks: 39).runningSeconds, 30)
        XCTAssertFalse(ContractionMath.status(timer, at: t0 + 180, weeks: 39).isLongRunning)
        XCTAssertTrue(ContractionMath.status(timer, at: t0 + 181, weeks: 39).isLongRunning)
        XCTAssertNil(ContractionMath.status(timer, at: t0 + 30, weeks: 39).summary, "还没有结束的宫缩")
    }

    // MARK: - 存档收窄（后端只收 1–500 项、start ≤ 86400）

    func testArchivedResultKeepsTheLast500WithTheFirstAtZero() throws {
        var timer = ContractionTimer()
        for i in 0..<520 {
            let start = t0 + TimeInterval(i * 100)
            _ = timer.toggle(at: start)
            _ = timer.toggle(at: start + 40)
        }
        let id = UUID()
        let result = try XCTUnwrap(timer.archivedResult(id: id))
        XCTAssertEqual(result.id, id)
        XCTAssertEqual(result.entries.count, 500)
        XCTAssertEqual(result.entries.first, ContractionEntry(start: 0, duration: 40))
        XCTAssertEqual(result.entries.last?.start, 499 * 100)
        XCTAssertEqual(result.startedAt, t0 + 20 * 100, "最早 20 次被丢掉，零点改为第 21 次的开始")
    }

    func testArchivedResultDropsContractionsMoreThanADayBeforeTheLastStart() throws {
        var timer = ContractionTimer()
        // 开始时刻 0、10000、…、100000 秒；最后一次在 100000，只留开始 ≥ 13600 的。
        for i in 0...10 {
            let start = t0 + TimeInterval(i * 10_000)
            _ = timer.toggle(at: start)
            _ = timer.toggle(at: start + 60)
        }
        let result = try XCTUnwrap(timer.archivedResult(id: UUID()))
        XCTAssertEqual(result.entries.count, 9)
        XCTAssertEqual(result.entries.first?.start, 0)
        XCTAssertEqual(result.entries.last?.start, 80_000)
        XCTAssertEqual(result.startedAt, t0 + 20_000)
    }

    func testArchivedResultKeepsExactlyOneDayAndSkipsTheRunningOne() throws {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0); _ = timer.toggle(at: t0 + 60)
        _ = timer.toggle(at: t0 + 86_400); _ = timer.toggle(at: t0 + 86_460)
        _ = timer.toggle(at: t0 + 90_000)  // 还在进行中，不存
        let result = try XCTUnwrap(timer.archivedResult(id: UUID()))
        XCTAssertEqual(result.entries.map(\.start), [0, 86_400])
        XCTAssertEqual(result.startedAt, t0)
        XCTAssertNil(ContractionTimer().archivedResult(id: UUID()), "没有已结束的宫缩")
    }

    // MARK: - 结果与格式

    func testResultDraftAndTitle() {
        let result = ContractionResult(
            id: UUID(), startedAt: t0,
            entries: (0..<12).map { ContractionEntry(start: $0 * 290, duration: 60) })
        XCTAssertEqual(result.title, "宫缩计时 · 12 次 · 约 4 分 50 秒一次")
        XCTAssertEqual(result.draft.type, .contraction)
        XCTAssertEqual(result.draft.visibility, .family)
        XCTAssertEqual(result.draft.occurredAt, t0)
        XCTAssertEqual(ContractionResult(id: UUID(), startedAt: t0,
                                         entries: [ContractionEntry(start: 0, duration: 60)]).title,
                       "宫缩计时 · 1 次")
    }

    func testFormatSeconds() {
        XCTAssertEqual(ContractionFormat.seconds(45), "45 秒")
        XCTAssertEqual(ContractionFormat.seconds(290), "4 分 50 秒")
        XCTAssertEqual(ContractionFormat.seconds(300), "5 分钟")
    }

    // MARK: - 从分娩页出发时关联哪次计时

    private func session(startedAt: Date, entries: [ContractionEntry]) -> ContractionSession {
        let record = RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .contraction, occurredAt: startedAt, visibility: .family, title: nil, content: nil,
            structuredData: .contraction(ContractionRecordData(contractions: entries, summary: nil)),
            attachmentRefs: [], createdAt: startedAt, updatedAt: startedAt)
        return ContractionSession(record: record)!
    }

    private func timer(_ spans: [(TimeInterval, TimeInterval?)]) -> ContractionTimer {
        var timer = ContractionTimer()
        for (start, end) in spans {
            _ = timer.toggle(at: t0 + start)
            if let end { _ = timer.toggle(at: t0 + end) }
        }
        return timer
    }

    func testTripLinkFinishesAnActiveTimerThatHasCompletedContractions() {
        let recent = session(startedAt: t0, entries: [ContractionEntry(start: 0, duration: 60)])
        let active = timer([(0, 60), (300, nil)])
        XCTAssertEqual(HospitalTripLink.decide(active: active, latest: recent, now: t0 + 400), .finishActive)
    }

    func testTripLinkAttachesTheLatestSessionWhenItsLastContractionIsWithinTwoHours() {
        // 最后一次宫缩 = 开始时刻 + 最后一项的 start + duration = t0 + 1000 + 60。
        let latest = session(startedAt: t0, entries: [ContractionEntry(start: 0, duration: 60),
                                                      ContractionEntry(start: 1000, duration: 60)])
        let lastEnd: TimeInterval = 1060
        XCTAssertEqual(HospitalTripLink.decide(active: nil, latest: latest, now: t0 + lastEnd + 7200),
                       .existing(latest.id), "恰好 2 小时仍关联")
        XCTAssertEqual(HospitalTripLink.decide(active: nil, latest: latest, now: t0 + lastEnd + 7201), .none,
                       "按最后一次宫缩算，不按开始时刻：开始时刻已过 2 小时 17 分")
        XCTAssertEqual(HospitalTripLink.lastContractionEnd(of: latest), t0 + lastEnd)
    }

    func testTripLinkWithOnlyARunningContractionFallsBackToTheLatestSession() {
        let latest = session(startedAt: t0, entries: [ContractionEntry(start: 0, duration: 60)])
        let running = timer([(600, nil)])
        XCTAssertEqual(HospitalTripLink.decide(active: running, latest: latest, now: t0 + 700), .existing(latest.id))
    }

    func testTripLinkIsNoneWithoutAnyTiming() {
        XCTAssertEqual(HospitalTripLink.decide(active: nil, latest: nil, now: t0), .none)
        let old = session(startedAt: t0, entries: [ContractionEntry(start: 0, duration: 60)])
        XCTAssertEqual(HospitalTripLink.decide(active: nil, latest: old, now: t0 + 86_400), .none)
    }

    func testTripLinkRequiresAChoiceForAStaleActiveTimer() {
        let active = timer([(0, 60)])
        let recent = session(startedAt: t0 + 21_000, entries: [ContractionEntry(start: 0, duration: 60)])
        XCTAssertEqual(HospitalTripLink.decide(active: active, latest: recent, now: t0 + 60 + 21_600), .finishActive)
        XCTAssertEqual(HospitalTripLink.decide(active: active, latest: recent, now: t0 + 60 + 21_601), .resolveStale,
                       "旧计时必须由用户处理，不能自动保存或改关联其他历史")
    }

    func testTripLinkDoesNotAttachAHistoryRecordFromTheFuture() {
        let future = session(startedAt: t0 + 600, entries: [ContractionEntry(start: 0, duration: 60)])
        XCTAssertEqual(HospitalTripLink.decide(active: nil, latest: future, now: t0), .none)
    }
}
