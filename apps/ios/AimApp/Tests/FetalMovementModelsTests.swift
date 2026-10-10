import XCTest
@testable import AimApp

final class FetalMovementModelsTests: XCTestCase {
    func testRecordTypeRoundTripsItsRawValue() {
        XCTAssertEqual(RecordType(rawValue: "fetal_movement"), .fetalMovement)
        XCTAssertEqual(RecordType.fetalMovement.rawValue, "fetal_movement")
        XCTAssertEqual(RecordType.fetalMovement.displayName, "胎动")
    }

    func testStructuredDataDecodesFromTheAPIShape() throws {
        let json = """
        {"duration_seconds":1920,"count":10,"target":10,"outcome":"reached","taps":[1,2,3,4,5,6,7,8,9,1920]}
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(APIRecordStructuredDataDTO.self, from: json)

        guard case let .fetalMovement(data) = dto.recordData(for: .fetalMovement) else {
            return XCTFail("应当解码为胎动")
        }
        XCTAssertEqual(data.durationSeconds, 1920)
        XCTAssertEqual(data.outcome, .reached)
        XCTAssertEqual(data.taps.count, 10)
    }

    func testUnknownOutcomeFallsBackToUnknownRecordData() throws {
        let json = """
        {"duration_seconds":60,"count":1,"target":10,"outcome":"normal","taps":[5]}
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(APIRecordStructuredDataDTO.self, from: json)
        XCTAssertEqual(dto.recordData(for: .fetalMovement), .unknown)
    }

    func testStructuredDataEncodesTheAPIKeys() throws {
        let data = FetalMovementRecordData(durationSeconds: 7200, count: 6, target: 10, outcome: .under, taps: [1, 2, 3, 4, 5, 6])
        let encoded = try JSONEncoder().encode(APIRecordStructuredDataDTO(recordData: .fetalMovement(data)))
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertEqual(object?["duration_seconds"] as? Int, 7200)
        XCTAssertEqual(object?["outcome"] as? String, "under")
        XCTAssertEqual(object?["target"] as? Int, 10)
        XCTAssertEqual((object?["taps"] as? [Int])?.count, 6)
    }

    func testReportedLessDecodesAndDefaultsToFalse() throws {
        let with = """
        {"duration_seconds":90,"count":0,"target":10,"outcome":"stopped","taps":[],"reported_less":true}
        """.data(using: .utf8)!
        let without = """
        {"duration_seconds":90,"count":0,"target":10,"outcome":"stopped","taps":[]}
        """.data(using: .utf8)!
        guard case let .fetalMovement(reported) = try JSONDecoder().decode(APIRecordStructuredDataDTO.self, from: with)
                .recordData(for: .fetalMovement),
              case let .fetalMovement(plain) = try JSONDecoder().decode(APIRecordStructuredDataDTO.self, from: without)
                .recordData(for: .fetalMovement)
        else { return XCTFail("应当解码为胎动") }
        XCTAssertTrue(reported.reportedLess)
        XCTAssertFalse(plain.reportedLess, "旧记录没有这个字段，按没报告处理")
    }

    /// 只在报告过时才发这个字段，旧服务端和没报告的记录都不受影响。
    func testReportedLessIsEncodedOnlyWhenTrue() throws {
        func encoded(_ reportedLess: Bool) throws -> [String: Any]? {
            let data = FetalMovementRecordData(
                durationSeconds: 90, count: 0, target: 10, outcome: .stopped, taps: [], reportedLess: reportedLess)
            let json = try JSONEncoder().encode(APIRecordStructuredDataDTO(recordData: .fetalMovement(data)))
            return try JSONSerialization.jsonObject(with: json) as? [String: Any]
        }
        XCTAssertEqual(try encoded(true)?["reported_less"] as? Bool, true)
        XCTAssertNil(try encoded(false)?["reported_less"])

        // 编码再解码回来仍是同一条。
        let original = FetalMovementRecordData(
            durationSeconds: 90, count: 0, target: 10, outcome: .stopped, taps: [], reportedLess: true)
        let dto = try JSONDecoder().decode(
            APIRecordStructuredDataDTO.self,
            from: JSONEncoder().encode(APIRecordStructuredDataDTO(recordData: .fetalMovement(original))))
        XCTAssertEqual(dto.recordData(for: .fetalMovement), .fetalMovement(original))
    }

    /// 升级前落盘的未保存结果没有 reportedLess，升级后要还能读出来重试。
    func testAResultSavedBeforeReportedLessExistedStillDecodes() throws {
        let json = """
        {"startedAt":0,"durationSeconds":600,"count":4,"outcome":"stopped","taps":[1,2,3,4]}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(FetalMovementResult.self, from: json)
        XCTAssertFalse(result.reportedLess)
        XCTAssertEqual(result.count, 4)

        var reported = result
        reported.reportedLess = true
        let restored = try JSONDecoder().decode(FetalMovementResult.self, from: JSONEncoder().encode(reported))
        XCTAssertEqual(restored, reported)
        XCTAssertTrue(restored.recordData.reportedLess)
    }

    func testSummaryMentionsReportedLess() {
        XCTAssertEqual(
            FetalMovementFormat.summary(.init(durationSeconds: 600, count: 4, target: 10, outcome: .stopped, taps: [],
                                              reportedLess: true)),
            "4 次 · 10 分钟 · 未数完 · 感觉胎动少了")
    }

    /// 胎动记录由计数页生成，通用编辑器改不了它的结构化数据；详情页只留删除。
    func testFetalMovementRecordsAreNotEditableInTheComposer() {
        XCTAssertFalse(RecordType.fetalMovement.canEditInComposer)
        XCTAssertTrue(RecordType.symptom.canEditInComposer)
        XCTAssertTrue(RecordType.note.canEditInComposer)
    }

    func testFormatting() {
        XCTAssertEqual(FetalMovementFormat.duration(40), "不到 1 分钟")
        XCTAssertEqual(FetalMovementFormat.duration(1920), "32 分钟")
        XCTAssertEqual(FetalMovementFormat.duration(1921), "33 分钟")
        XCTAssertEqual(FetalMovementFormat.duration(7200), "2 小时")
        XCTAssertEqual(FetalMovementFormat.duration(4500), "1 小时 15 分钟")
        XCTAssertEqual(
            FetalMovementFormat.summary(.init(durationSeconds: 1920, count: 10, target: 10, outcome: .reached, taps: [])),
            "10 次 · 32 分钟")
        XCTAssertEqual(
            FetalMovementFormat.summary(.init(durationSeconds: 7200, count: 6, target: 10, outcome: .under, taps: [])),
            "2 小时 6 次 · 不足 10 次")
        XCTAssertEqual(
            FetalMovementFormat.summary(.init(durationSeconds: 600, count: 4, target: 10, outcome: .stopped, taps: [])),
            "4 次 · 10 分钟 · 未数完")
    }

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func counter(dedupe: TimeInterval = 3) -> FetalMovementCounter {
        FetalMovementCounter(startedAt: start, dedupeInterval: dedupe)
    }

    func testTapsWithinTheDedupeIntervalAreIgnored() {
        var c = counter()
        XCTAssertEqual(c.tap(at: start.addingTimeInterval(10)), .counted)
        XCTAssertEqual(c.tap(at: start.addingTimeInterval(12)), .ignored)
        XCTAssertEqual(c.tap(at: start.addingTimeInterval(13)), .counted)
        XCTAssertEqual(c.count, 2)
    }

    func testTheTenthTapReachesTheTargetAndEndsAtThatMoment() {
        var c = counter()
        for i in 1...9 { XCTAssertEqual(c.tap(at: start.addingTimeInterval(Double(i * 60))), .counted) }
        XCTAssertEqual(c.tap(at: start.addingTimeInterval(1920.4)), .reachedTarget)

        let result = c.result(at: start.addingTimeInterval(5000))
        XCTAssertEqual(result.outcome, .reached)
        XCTAssertEqual(result.durationSeconds, 1921)
        XCTAssertEqual(result.count, 10)
        XCTAssertEqual(result.taps.last, 1920)
        XCTAssertEqual(c.tap(at: start.addingTimeInterval(2000)), .reachedTarget, "数满后不再计数")
    }

    /// 第 10 次落在 7199.4 秒：向上取整为 7200，仍是 2 小时内数到，后端接受 ≤ 7200。
    func testTheTenthTapJustBeforeTwoHoursIsReachedAtTwoHours() {
        var c = counter()
        for i in 1...9 { _ = c.tap(at: start.addingTimeInterval(Double(i * 600))) }
        XCTAssertEqual(c.tap(at: start.addingTimeInterval(7199.4)), .reachedTarget)

        let result = c.result(at: start.addingTimeInterval(7300))
        XCTAssertEqual(result.outcome, .reached)
        XCTAssertEqual(result.durationSeconds, 7200)
    }

    func testTwoHoursWithoutTenIsUnder() {
        var c = counter()
        for i in 1...6 { _ = c.tap(at: start.addingTimeInterval(Double(i * 600))) }
        let late = start.addingTimeInterval(7200)
        XCTAssertTrue(c.isExpired(at: late))
        XCTAssertEqual(c.tap(at: late), .expired)

        let result = c.result(at: start.addingTimeInterval(9000))
        XCTAssertEqual(result.outcome, .under)
        XCTAssertEqual(result.durationSeconds, 7200, "超过 2 小时才回来，也按满 2 小时记")
        XCTAssertEqual(result.count, 6)
    }

    func testStoppingEarlyRecordsTheElapsedTime() {
        var c = counter()
        _ = c.tap(at: start.addingTimeInterval(30))
        let result = c.result(at: start.addingTimeInterval(600.9))
        XCTAssertEqual(result.outcome, .stopped)
        XCTAssertEqual(result.durationSeconds, 600)
        XCTAssertEqual(result.taps, [30])
    }

    func testStoppingAfterTheClockMovesBackStillCoversTheLastTap() {
        // 系统时钟回拨（NTP 校时或手动改时间）后，用时不能短于最后一次点击，否则后端校验不过。
        var c = counter()
        _ = c.tap(at: start.addingTimeInterval(600))
        for now in [start.addingTimeInterval(300), start.addingTimeInterval(-100)] {
            let result = c.result(at: now)
            XCTAssertEqual(result.outcome, .stopped)
            XCTAssertGreaterThanOrEqual(result.durationSeconds, result.taps.last ?? 0)
        }
    }

    func testTheCounterSurvivesARoundTripThroughJSON() throws {
        var c = counter()
        _ = c.tap(at: start.addingTimeInterval(42))
        let restored = try JSONDecoder().decode(FetalMovementCounter.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(restored, c)
    }

    func testResultBuildsAFamilyVisibleDraft() {
        let result = FetalMovementResult(startedAt: start, durationSeconds: 1920, count: 10, outcome: .reached, taps: Array(1...10))
        let draft = result.draft
        XCTAssertEqual(draft.type, .fetalMovement)
        XCTAssertEqual(draft.occurredAt, start)
        XCTAssertEqual(draft.visibility, .family)
        XCTAssertEqual(draft.title, "数胎动 10 次 · 32 分钟")
        XCTAssertEqual(draft.structuredData, .fetalMovement(result.recordData))
    }

    private func session(_ daysAgo: Int, hour: Int = 20, seconds: Int, outcome: FetalMovementOutcome = .reached) -> FetalMovementSession {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: start)!
        let at = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return FetalMovementSession(
            id: UUID(), startedAt: at,
            data: FetalMovementRecordData(durationSeconds: seconds, count: outcome == .reached ? 10 : 6,
                                          target: 10, outcome: outcome, taps: []))
    }

    func testBaselineIsTheMedianOfTheLastSevenReachedSessions() {
        XCTAssertNil(FetalMovementInsights.baselineSeconds([session(1, seconds: 600), session(2, seconds: 700)]),
                     "不足 3 次不算平时")
        let sessions = [
            session(1, seconds: 600), session(2, seconds: 900), session(3, seconds: 700),
            session(4, seconds: 7200, outcome: .under),
            session(5, seconds: 800), session(6, seconds: 650), session(7, seconds: 750),
            session(8, seconds: 720), session(9, seconds: 5000),
        ]
        // 取最近 7 次 reached：600 900 700 800 650 750 720 → 中位数 720；第 9 天的 5000 不在其中。
        XCTAssertEqual(FetalMovementInsights.baselineSeconds(sessions), 720)
    }

    func testSlowNeedsBothDoubleTheBaselineAndHalfAnHour() {
        XCTAssertTrue(FetalMovementInsights.isSlow(durationSeconds: 2000, baselineSeconds: 900))
        XCTAssertFalse(FetalMovementInsights.isSlow(durationSeconds: 1700, baselineSeconds: 600), "不到 30 分钟不提醒")
        XCTAssertFalse(FetalMovementInsights.isSlow(durationSeconds: 1900, baselineSeconds: 1000), "没到平时的 2 倍")
        XCTAssertFalse(FetalMovementInsights.isSlow(durationSeconds: 5000, baselineSeconds: nil))
    }

    func testDailyTrendTakesTheFirstReachedSessionOfEachDayAndFlagsUnder() {
        let calendar = Calendar(identifier: .gregorian)
        let sessions = [
            session(0, hour: 21, seconds: 900),
            session(0, hour: 9, seconds: 600),
            session(1, hour: 20, seconds: 7200, outcome: .under),
        ]
        let trend = FetalMovementInsights.dailyTrend(sessions, days: 3, now: start, calendar: calendar)

        XCTAssertEqual(trend.count, 3)
        XCTAssertEqual(trend.last?.reachedSeconds, 600, "当天取最早完成的那次")
        XCTAssertEqual(trend[1].reachedSeconds, nil)
        XCTAssertTrue(trend[1].hadUnder)
        XCTAssertEqual(trend.first?.reachedSeconds, nil)
        XCTAssertFalse(trend.first?.hadUnder ?? true)
    }

    func testLatestSessionOfTheDay() {
        let calendar = Calendar(identifier: .gregorian)
        let sessions = [session(0, hour: 9, seconds: 600), session(0, hour: 21, seconds: 900), session(1, seconds: 500)]
        XCTAssertEqual(FetalMovementInsights.latest(onDayOf: start, in: sessions, calendar: calendar)?.data.durationSeconds, 900)
    }
}
