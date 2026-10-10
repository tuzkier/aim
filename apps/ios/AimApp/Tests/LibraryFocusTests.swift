import XCTest
@testable import AimApp

@MainActor
final class LibraryFocusTests: XCTestCase {
    private static let severeHeadline = "血压很高，请立即联系产检医院或去急诊"
    private static let soonHeadline = "血压连续偏高，今天联系你的产检医院"
    private static let recheckHeadline = "上次血压很高，今天联系产检医院复测"

    private func bp(_ systolic: Double?, _ diastolic: Double?) -> CheckupMetrics {
        CheckupMetrics(systolic: systolic, diastolic: diastolic)
    }

    private func checkup(daysAgo: Int, metrics: CheckupMetrics) -> RecordItem {
        checkup(at: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!, metrics: metrics)
    }

    private func checkup(at when: Date, metrics: CheckupMetrics) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .checkup, occurredAt: when, visibility: .family, title: nil, content: nil,
            structuredData: .checkup(CheckupRecordData(
                hospital: "市一医院", examItems: "常规", result: "正常",
                doctorAdvice: "按时复查", metrics: metrics)),
            attachmentRefs: [], createdAt: when, updatedAt: when
        )
    }

    private func question(_ text: String, answered: Bool) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .question, occurredAt: .now, visibility: .family, title: nil, content: text,
            structuredData: .question(QuestionRecordData(answered: answered, answer: nil)),
            attachmentRefs: [], createdAt: .now, updatedAt: .now
        )
    }

    private func symptom(_ label: String, daysAgo: Int) -> RecordItem {
        let when = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .symptom, occurredAt: when, visibility: .family, title: nil, content: nil,
            structuredData: .symptom(SymptomRecordData(symptoms: [label], severity: 3, note: nil)),
            attachmentRefs: [], createdAt: when, updatedAt: when
        )
    }

    /// 没有值得关注的事就不显示——空的横幅比没有横幅更糟。
    func testNothingWorthShowingMeansNoBanner() {
        XCTAssertNil(LibraryFocus.make(from: LibrarySnapshot()))
    }

    /// 连续两次收缩压偏高才提示。单次偏高很常见（紧张、刚走完路），
    /// 一次就报会让用户很快学会忽略这个位置。
    func testASingleHighReadingIsNotEnough() {
        let snapshot = LibrarySnapshot(records: [
            checkup(daysAgo: 30, metrics: CheckupMetrics(systolic: 118, diastolic: 75)),
            checkup(daysAgo: 1, metrics: CheckupMetrics(systolic: 142, diastolic: 92)),
        ])

        XCTAssertNil(LibraryFocus.make(from: snapshot))
    }

    func testTwoConsecutiveHighReadingsAreSurfaced() {
        let snapshot = LibrarySnapshot(records: [
            checkup(daysAgo: 30, metrics: CheckupMetrics(systolic: 145, diastolic: 92)),
            checkup(daysAgo: 1, metrics: CheckupMetrics(systolic: 148, diastolic: 95)),
        ])

        let focus = LibraryFocus.make(from: snapshot)

        XCTAssertNotNil(focus)
        XCTAssertTrue(focus!.headline.contains("血压"))
    }

    /// 连续两次 ≥140/90 要今天联系医院，不能再等下次产检——和危险信号的口径一致。
    func testTwoConsecutiveHighReadingsMeanContactTheHospitalToday() {
        let snapshot = LibrarySnapshot(records: [
            checkup(daysAgo: 30, metrics: CheckupMetrics(systolic: 145, diastolic: 92)),
            checkup(daysAgo: 1, metrics: CheckupMetrics(systolic: 148, diastolic: 95)),
        ])

        XCTAssertEqual(LibraryFocus.make(from: snapshot)?.headline, "血压连续偏高，今天联系你的产检医院")
    }

    /// 只有舒张压到 90 也算偏高——140/90 是「或」的关系。
    func testDiastolicAloneCountsTowardsConsecutiveHighReadings() {
        let snapshot = LibrarySnapshot(records: [
            checkup(daysAgo: 30, metrics: CheckupMetrics(systolic: 130, diastolic: 92)),
            checkup(daysAgo: 1, metrics: CheckupMetrics(systolic: 132, diastolic: 95)),
        ])

        XCTAssertEqual(LibraryFocus.make(from: snapshot)?.headline, "血压连续偏高，今天联系你的产检医院")
    }

    /// 最近一次高压 ≥160 或低压 ≥110 是危险信号的升档线：一次就够，要立即就医。
    func testASingleSeverelyHighReadingMeansSeekCareNow() {
        for metrics in [CheckupMetrics(systolic: 162, diastolic: 100),
                        CheckupMetrics(systolic: 150, diastolic: 110)] {
            let snapshot = LibrarySnapshot(records: [
                checkup(daysAgo: 30, metrics: CheckupMetrics(systolic: 118, diastolic: 75)),
                checkup(daysAgo: 1, metrics: metrics),
                question("能继续游泳吗", answered: false),
            ])

            XCTAssertEqual(LibraryFocus.make(from: snapshot)?.headline,
                           "血压很高，请立即联系产检医院或去急诊")
        }
    }

    /// 很高的那次已经过去、最近一次回落了，就不再按立即就医提示。
    func testOnlyTheLatestReadingDecidesTheSevereLevel() {
        let snapshot = LibrarySnapshot(records: [
            checkup(daysAgo: 30, metrics: CheckupMetrics(systolic: 165, diastolic: 112)),
            checkup(daysAgo: 1, metrics: CheckupMetrics(systolic: 118, diastolic: 75)),
        ])

        // 最近一次正常、也不是连续两次偏高，血压规则不该出声；快照里没有别的事可提。
        XCTAssertNil(LibraryFocus.make(from: snapshot))
    }

    /// 提示只说该去联系谁，不下判断——这是医疗内容的红线。
    func testTheBloodPressurePromptDefersToTheHospital() {
        let snapshot = LibrarySnapshot(records: [
            checkup(daysAgo: 30, metrics: CheckupMetrics(systolic: 145, diastolic: 92)),
            checkup(daysAgo: 1, metrics: CheckupMetrics(systolic: 148, diastolic: 95)),
        ])

        let headline = LibraryFocus.make(from: snapshot)!.headline

        XCTAssertTrue(headline.contains("产检医院"))
        for verdict in ["高血压", "妊高症", "子痫", "确诊", "建议服药"] {
            XCTAssertFalse(headline.contains(verdict), "不该出现诊断性措辞：\(verdict)")
        }
    }

    func testPendingQuestionsAreSurfacedWhenNothingIsUrgent() {
        let snapshot = LibrarySnapshot(records: [
            question("能继续游泳吗", answered: false),
            question("要补钙吗", answered: false),
        ])

        let focus = LibraryFocus.make(from: snapshot)

        XCTAssertTrue(focus!.headline.contains("2"))
        XCTAssertTrue(focus!.tags.contains { $0.contains("待问医生") })
    }

    /// 血压比攒问题更要紧，同时命中时血压排前面。
    func testUrgentSignalsOutrankHousekeeping() {
        let snapshot = LibrarySnapshot(records: [
            checkup(daysAgo: 30, metrics: CheckupMetrics(systolic: 145, diastolic: 92)),
            checkup(daysAgo: 1, metrics: CheckupMetrics(systolic: 148, diastolic: 95)),
            question("能继续游泳吗", answered: false),
        ])

        XCTAssertTrue(LibraryFocus.make(from: snapshot)!.headline.contains("血压"))
    }

    /// 同一个症状一周内反复出现值得被看见。
    func testRepeatedSymptomsAreSurfaced() {
        let snapshot = LibrarySnapshot(records: [
            symptom("头晕", daysAgo: 1),
            symptom("头晕", daysAgo: 2),
            symptom("头晕", daysAgo: 4),
        ])

        let focus = LibraryFocus.make(from: snapshot)

        XCTAssertTrue(focus!.headline.contains("头晕"))
    }

    // MARK: - 血压档位与时效

    func testSevereReadingIsUrgentAndOtherRulesAreNot() {
        let severe = LibraryFocus.make(from: LibrarySnapshot(records: [
            checkup(daysAgo: 3, metrics: bp(165, 112)),
        ]))
        XCTAssertEqual(severe?.headline, Self.severeHeadline)
        XCTAssertEqual(severe?.level, .urgent)

        let consecutive = LibraryFocus.make(from: LibrarySnapshot(records: [
            checkup(daysAgo: 10, metrics: bp(145, 92)),
            checkup(daysAgo: 3, metrics: bp(148, 95)),
        ]))
        XCTAssertEqual(consecutive?.level, .soon)

        let questions = LibraryFocus.make(from: LibrarySnapshot(records: [
            question("要补钙吗", answered: false),
        ]))
        XCTAssertEqual(questions?.level, .info)
    }

    /// 很高档只看 7 天内的读数：8 天前量的已经不是「现在」的情况，
    /// 但也不能不说话——降为今天联系医院复测。
    func testASevereReadingOlderThanAWeekAsksForARecheck() {
        let stale = LibrarySnapshot(records: [
            checkup(daysAgo: 30, metrics: bp(118, 75)),
            checkup(daysAgo: 8, metrics: bp(165, 112)),
        ])
        let focus = LibraryFocus.make(from: stale)
        XCTAssertEqual(focus?.level, .soon)
        XCTAssertEqual(focus?.headline, Self.recheckHeadline)

        let fresh = LibrarySnapshot(records: [
            checkup(daysAgo: 30, metrics: bp(118, 75)),
            checkup(daysAgo: 3, metrics: bp(165, 112)),
        ])
        XCTAssertEqual(LibraryFocus.make(from: fresh)?.headline, Self.severeHeadline)
    }

    /// 连续偏高档要求最近一次在 14 天内；超时的交给后续规则。
    func testConsecutiveHighReadingsExpireAfterTwoWeeks() {
        let stale = LibrarySnapshot(records: [
            checkup(daysAgo: 40, metrics: bp(145, 92)),
            checkup(daysAgo: 15, metrics: bp(148, 95)),
            question("能继续游泳吗", answered: false),
        ])
        XCTAssertEqual(LibraryFocus.make(from: stale)?.headline, "攒了 1 个问题，下次产检一次带走")

        let fresh = LibrarySnapshot(records: [
            checkup(daysAgo: 40, metrics: bp(145, 92)),
            checkup(daysAgo: 13, metrics: bp(148, 95)),
        ])
        XCTAssertEqual(LibraryFocus.make(from: fresh)?.headline, Self.soonHeadline)
    }

    /// 时效按注入的 now 算，而不是写死的系统时间。
    func testFreshnessIsMeasuredAgainstTheInjectedNow() {
        let snapshot = LibrarySnapshot(records: [checkup(daysAgo: 3, metrics: bp(165, 112))])
        let fiveDaysLater = Calendar.current.date(byAdding: .day, value: 5, to: .now)!
        let twelveDaysLater = Calendar.current.date(byAdding: .day, value: 12, to: .now)!

        XCTAssertEqual(LibraryFocus.make(from: snapshot)?.level, .urgent)
        XCTAssertEqual(LibraryFocus.make(from: snapshot, now: fiveDaysLater)?.level, .soon)
        XCTAssertNil(LibraryFocus.make(from: snapshot, now: twelveDaysLater))
    }

    /// 160/110 恰好在线就算很高；159/109 不算，但仍够得上「偏高」。
    func testSevereThresholdIsInclusive() {
        for metrics in [bp(160, 100), bp(150, 110), bp(160, 110)] {
            let snapshot = LibrarySnapshot(records: [checkup(daysAgo: 1, metrics: metrics)])
            XCTAssertEqual(LibraryFocus.make(from: snapshot)?.level, .urgent, "\(metrics)")
        }

        let justBelow = LibrarySnapshot(records: [
            checkup(daysAgo: 30, metrics: bp(118, 75)),
            checkup(daysAgo: 1, metrics: bp(159, 109)),
        ])
        XCTAssertNil(LibraryFocus.make(from: justBelow), "单次 159/109 既不到升档线，也不算连续偏高")

        let twiceJustBelow = LibrarySnapshot(records: [
            checkup(daysAgo: 8, metrics: bp(159, 109)),
            checkup(daysAgo: 1, metrics: bp(159, 109)),
        ])
        XCTAssertEqual(LibraryFocus.make(from: twiceJustBelow)?.level, .soon)
    }

    /// 140/90 恰好在线就算偏高，高压低压满足一边即可；139/89 不算。
    func testHighThresholdIsInclusive() {
        let onTheLine = LibrarySnapshot(records: [
            checkup(daysAgo: 8, metrics: bp(140, 85)),
            checkup(daysAgo: 1, metrics: bp(135, 90)),
        ])
        XCTAssertEqual(LibraryFocus.make(from: onTheLine)?.headline, Self.soonHeadline)

        let justBelow = LibrarySnapshot(records: [
            checkup(daysAgo: 8, metrics: bp(139, 89)),
            checkup(daysAgo: 1, metrics: bp(139, 89)),
        ])
        XCTAssertNil(LibraryFocus.make(from: justBelow))
    }

    /// 只记了一边的读数也要认：只有高压或只有低压到了升档线，同样立即就医。
    func testSingleSidedReadingsAreJudgedOnWhatWasRecorded() {
        for metrics in [bp(165, nil), bp(nil, 112)] {
            let snapshot = LibrarySnapshot(records: [checkup(daysAgo: 1, metrics: metrics)])
            XCTAssertEqual(LibraryFocus.make(from: snapshot)?.level, .urgent, "\(metrics)")
        }

        let diastolicOnly = LibrarySnapshot(records: [
            checkup(daysAgo: 8, metrics: bp(nil, 92)),
            checkup(daysAgo: 1, metrics: bp(nil, 95)),
        ])
        XCTAssertEqual(LibraryFocus.make(from: diastolicOnly)?.headline, Self.soonHeadline)

        // 没测血压的产检（只有体重）不算一次读数，不能把「连续」打断。
        let weightInBetween = LibrarySnapshot(records: [
            checkup(daysAgo: 10, metrics: bp(145, 92)),
            checkup(daysAgo: 5, metrics: CheckupMetrics(weightKg: 60)),
            checkup(daysAgo: 1, metrics: bp(148, nil)),
        ])
        XCTAssertEqual(LibraryFocus.make(from: weightInBetween)?.headline, Self.soonHeadline)
    }

    /// 血压和反复症状同时命中时，血压排前面。
    func testBloodPressureOutranksRepeatedSymptoms() {
        let snapshot = LibrarySnapshot(records: [
            symptom("头晕", daysAgo: 1),
            symptom("头晕", daysAgo: 2),
            symptom("头晕", daysAgo: 4),
            checkup(daysAgo: 10, metrics: bp(145, 92)),
            checkup(daysAgo: 1, metrics: bp(148, 95)),
        ])

        XCTAssertEqual(LibraryFocus.make(from: snapshot)?.headline, Self.soonHeadline)
    }

    /// 8–14 天前很高、前一次也偏高：复测这条比「连续偏高」更具体，优先用它。
    func testStaleSevereReadingOutranksConsecutiveHighReadings() {
        let snapshot = LibrarySnapshot(records: [
            checkup(daysAgo: 20, metrics: bp(145, 92)),
            checkup(daysAgo: 10, metrics: bp(165, 112)),
        ])

        let focus = LibraryFocus.make(from: snapshot)
        XCTAssertEqual(focus?.level, .soon)
        XCTAssertEqual(focus?.headline, Self.recheckHeadline)
    }

    /// 7 天、14 天恰好在线都还算数，再多一天就换档或不提示。时间用注入的 now 固定住。
    func testFreshnessBoundariesAreInclusive() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
        func reading(daysBefore days: Int, _ metrics: CheckupMetrics) -> RecordItem {
            checkup(at: calendar.date(byAdding: .day, value: -days, to: now)!, metrics: metrics)
        }
        func make(_ records: [RecordItem]) -> LibraryFocus? {
            LibraryFocus.make(from: LibrarySnapshot(records: records), now: now)
        }

        XCTAssertEqual(make([reading(daysBefore: 7, bp(165, 112))])?.level, .urgent)
        XCTAssertEqual(make([reading(daysBefore: 8, bp(165, 112))])?.headline, Self.recheckHeadline)
        XCTAssertEqual(make([reading(daysBefore: 14, bp(165, 112))])?.headline, Self.recheckHeadline)
        XCTAssertNil(make([reading(daysBefore: 15, bp(165, 112))]))

        let previous = reading(daysBefore: 30, bp(145, 92))
        XCTAssertEqual(make([previous, reading(daysBefore: 14, bp(148, 95))])?.headline,
                       Self.soonHeadline)
        XCTAssertNil(make([previous, reading(daysBefore: 15, bp(148, 95))]))
    }

    // MARK: - 最近报告有异常

    private static let abnormalHeadline = "最近报告有 2 项异常，记得问医生"

    private func report(id: UUID = UUID(), daysAgo: Int, items: [CheckupOtherItem],
                        metrics: CheckupMetrics = CheckupMetrics()) -> RecordItem {
        let when = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return RecordItem(
            id: id, pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .checkup, occurredAt: when, visibility: .family, title: nil, content: nil,
            structuredData: .checkup(CheckupRecordData(
                hospital: nil, examItems: nil, result: nil, doctorAdvice: nil,
                metrics: metrics, otherItems: items)),
            attachmentRefs: [], createdAt: when, updatedAt: when)
    }

    private func reportQuestion(_ text: String, reportID: UUID) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .question, occurredAt: .now, visibility: .family, title: nil, content: text,
            structuredData: .question(QuestionRecordData(answered: false, answer: nil, reportID: reportID)),
            attachmentRefs: [], createdAt: .now, updatedAt: .now)
    }

    private let flaggedItems = [
        CheckupOtherItem(name: "尿蛋白", value: "+", flag: .abnormal),
        CheckupOtherItem(name: "尿糖", value: "阴性"),
        CheckupOtherItem(name: "血小板", value: "98", flag: .low),
    ]

    /// 30 天内最新一份报告有 2 项标了异常、还没加进想问医生：提醒去问，点进报告详情。
    func testRecentReportWithFlaggedItemsReminds() {
        let id = UUID()
        let snapshot = LibrarySnapshot(records: [report(id: id, daysAgo: 3, items: flaggedItems)])

        let focus = LibraryFocus.make(from: snapshot)

        XCTAssertEqual(focus?.headline, Self.abnormalHeadline)
        XCTAssertEqual(focus?.level, .info)
        XCTAssertEqual(focus?.reportID, id)
    }

    /// 异常项都已经有对应问题（指回这份报告），就不再提醒。
    func testNoReminderOnceEveryFlaggedItemHasAQuestion() {
        let id = UUID()
        let snapshot = LibrarySnapshot(records: [
            report(id: id, daysAgo: 3, items: flaggedItems),
            reportQuestion("尿蛋白一个加号要紧吗", reportID: id),
            reportQuestion("血小板偏低要复查吗", reportID: id),
        ])

        // 不再提醒报告异常；轮到下一条规则——这两个问题还没问。
        let focus = LibraryFocus.make(from: snapshot)
        XCTAssertNil(focus?.reportID)
        XCTAssertEqual(focus?.headline, "攒了 2 个问题，下次产检一次带走")
    }

    /// 只问了一项还不够：仍然提醒。
    func testReminderStaysWhileSomeFlaggedItemsAreNotAsked() {
        let id = UUID()
        let snapshot = LibrarySnapshot(records: [
            report(id: id, daysAgo: 3, items: flaggedItems),
            reportQuestion("尿蛋白一个加号要紧吗", reportID: id),
        ])

        XCTAssertEqual(LibraryFocus.make(from: snapshot)?.headline, Self.abnormalHeadline)
    }

    func testReportsOlderThanThirtyDaysAreNotSurfaced() {
        let snapshot = LibrarySnapshot(records: [report(daysAgo: 31, items: flaggedItems)])

        XCTAssertNil(LibraryFocus.make(from: snapshot))
    }

    /// 只看最新一份：最新那份没有异常，就不翻更早的。
    func testOnlyTheLatestReportCounts() {
        let snapshot = LibrarySnapshot(records: [
            report(daysAgo: 10, items: flaggedItems),
            report(daysAgo: 2, items: [CheckupOtherItem(name: "尿糖", value: "阴性")]),
        ])

        XCTAssertNil(LibraryFocus.make(from: snapshot))
    }

    func testBloodPressureStillOutranksAbnormalReport() {
        let snapshot = LibrarySnapshot(records: [
            checkup(daysAgo: 8, metrics: bp(145, 92)),
            report(daysAgo: 1, items: flaggedItems, metrics: bp(148, 95)),
        ])

        XCTAssertEqual(LibraryFocus.make(from: snapshot)?.headline, Self.soonHeadline)
    }

    func testAbnormalReportOutranksRepeatedSymptoms() {
        let snapshot = LibrarySnapshot(records: [
            report(daysAgo: 1, items: flaggedItems),
            symptom("头晕", daysAgo: 1),
            symptom("头晕", daysAgo: 2),
            symptom("头晕", daysAgo: 4),
        ])

        XCTAssertEqual(LibraryFocus.make(from: snapshot)?.headline, Self.abnormalHeadline)
    }
}
