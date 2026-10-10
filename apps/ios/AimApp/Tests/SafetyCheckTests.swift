import XCTest
@testable import AimApp

@MainActor
final class SafetyCheckTests: XCTestCase {
    private func rule(_ id: String, severity: String) -> SafetyRule {
        SafetyRule(id: id, condition: "情况 \(id)", action: "处理 \(id)",
                   severity: severity, sourceURL: "https://example.test")
    }

    private let rules = [
        SafetyRule(id: "bleeding", condition: "出血量明显增加", action: "立即联系产检医院",
                   severity: "urgent", sourceURL: "https://example.test"),
        SafetyRule(id: "fever", condition: "高热", action: "立即寻求线下医疗帮助",
                   severity: "urgent", sourceURL: "https://example.test"),
        SafetyRule(id: "swelling", condition: "轻微水肿", action: "下次产检时告诉医生",
                   severity: "routine", sourceURL: "https://example.test"),
    ]

    /// 什么都没勾时不给结论——凭空说「你没事」比不说更危险。
    func testNothingSelectedGivesNoVerdict() {
        XCTAssertNil(SafetyCheck.verdict(for: [], in: rules))
    }

    /// 勾中任何一条紧急项，结论就是立即就医，不做加权也不做打折。
    func testAnyUrgentSelectionMeansSeekCareNow() {
        let verdict = SafetyCheck.verdict(for: ["bleeding"], in: rules)

        XCTAssertEqual(verdict?.level, .now)
        XCTAssertTrue(verdict!.headline.contains("立即"))
    }

    /// 紧急项和普通项同时勾中，按最严重的那条给结论。
    func testTheMostSevereSelectionWins() {
        XCTAssertEqual(SafetyCheck.verdict(for: ["swelling", "bleeding"], in: rules)?.level, .now)
    }

    func testOnlyRoutineSelectionsSuggestMentioningItAtTheNextVisit() {
        let verdict = SafetyCheck.verdict(for: ["swelling"], in: rules)

        XCTAssertEqual(verdict?.level, .mention)
        XCTAssertFalse(verdict!.headline.contains("立即"))
    }

    /// 结论里要带上勾中条目自己的处理建议，而不是笼统一句话。
    func testTheVerdictCarriesTheMatchingActions() {
        let verdict = SafetyCheck.verdict(for: ["bleeding", "fever"], in: rules)

        XCTAssertEqual(verdict?.actions.count, 2)
        XCTAssertTrue(verdict!.actions.contains("立即联系产检医院"))
    }

    /// 不认识的 id 直接忽略，不能因为一条脏数据就给出错误结论。
    func testUnknownSelectionsAreIgnored() {
        XCTAssertNil(SafetyCheck.verdict(for: ["not-a-rule"], in: rules))
    }

    // MARK: - 三档

    private func rule(_ id: String, severity: String, weeks: [Int]?) -> SafetyRule {
        SafetyRule(id: id, condition: "情况 \(id)", action: "处理 \(id)",
                   severity: severity, sourceURL: "https://example.test", weeks: weeks)
    }

    private var threeTierRules: [SafetyRule] {
        [
            rule("itching", severity: "same_day", weeks: nil),
            rule("swelling", severity: "routine", weeks: nil),
            rule("early-bleeding", severity: "urgent", weeks: [4, 13]),
            rule("fever", severity: "urgent", weeks: nil),
            rule("late-bleeding", severity: "urgent", weeks: [20, 42]),
            rule("mild-fever", severity: "same_day", weeks: nil),
        ]
    }

    /// 紧急项与当天联系项同时勾中，按紧急处理。
    func testUrgentOutranksSameDay() {
        let verdict = SafetyCheck.verdict(for: ["itching", "fever"], in: threeTierRules)

        XCTAssertEqual(verdict?.level, .now)
        XCTAssertEqual(verdict?.headline, "请立即联系产检医院或拨打 120")
    }

    /// 只勾当天联系项：今天或明天联系医院，不必半夜跑急诊。
    func testSameDayOnlyMeansContactTheHospitalSoon() {
        let verdict = SafetyCheck.verdict(for: ["itching", "swelling"], in: threeTierRules)

        XCTAssertEqual(verdict?.level, .soon)
        XCTAssertEqual(verdict?.headline, "今天或明天联系你的产检医院")
        XCTAssertEqual(verdict?.actions, ["处理 itching", "处理 swelling"])
    }

    func testRoutineOnlyStillMeansMentionAtTheNextVisit() {
        XCTAssertEqual(SafetyCheck.verdict(for: ["swelling"], in: threeTierRules)?.level, .mention)
    }

    /// 20 周后的出血会同时命中两条紧急项，两条都显示，勾哪条都是立即就医。
    func testOverlappingBleedingRulesBothMeanSeekCareNow() {
        let rules = [rule("urgent-bleeding", severity: "urgent", weeks: nil)]
            + threeTierRules
        let shown = SafetyCheck.rules(rules, forWeek: 34).map(\.id)

        XCTAssertTrue(shown.contains("urgent-bleeding"))
        XCTAssertTrue(shown.contains("late-bleeding"))
        XCTAssertEqual(SafetyCheck.verdict(for: ["late-bleeding"], in: rules)?.level, .now)
        XCTAssertEqual(SafetyCheck.verdict(for: ["urgent-bleeding"], in: rules)?.level, .now)
    }

    /// 按孕周过滤：不在这段孕周的不显示，全程适用的照常显示；紧急在前，同档保持原序。
    func testRulesAreFilteredByWeekAndUrgentComeFirst() {
        let shown = SafetyCheck.rules(threeTierRules, forWeek: 34).map(\.id)

        XCTAssertEqual(shown, ["fever", "late-bleeding", "itching", "mild-fever", "swelling"])
    }

    /// 孕周取不到时宁可多显示，不能因为缺数据把紧急项藏起来。
    func testUnknownWeekShowsEveryRule() {
        let shown = SafetyCheck.rules(threeTierRules, forWeek: nil)

        XCTAssertEqual(shown.count, threeTierRules.count)
        XCTAssertEqual(shown.first?.isUrgent, true)
    }

    /// 孕周区间含两端。
    func testWeekRangeIsInclusive() {
        let early = rule("early-bleeding", severity: "urgent", weeks: [4, 13])

        XCTAssertTrue(early.applies(week: 4))
        XCTAssertTrue(early.applies(week: 13))
        XCTAssertFalse(early.applies(week: 14))
        XCTAssertTrue(early.applies(week: nil))
    }

    func testSameDayIsRecognised() {
        XCTAssertTrue(rule("x", severity: "same_day", weeks: nil).isSameDay)
        XCTAssertFalse(rule("x", severity: "urgent", weeks: nil).isSameDay)
    }

    /// 接口返回的 weeks 要能解出来；老数据没有这个字段也不能解析失败。
    func testDTODecodesWeeksAndToleratesItsAbsence() throws {
        let json = Data("""
        {"items": [
          {"id": "a", "condition": "c", "action": "x", "severity": "urgent",
           "source_url": "https://example.test", "weeks": [20, 42]},
          {"id": "b", "condition": "c", "action": "x", "severity": "routine",
           "source_url": "https://example.test", "weeks": null},
          {"id": "c", "condition": "c", "action": "x", "severity": "same_day",
           "source_url": "https://example.test"}
        ]}
        """.utf8)
        let rules = try JSONDecoder().decode(APISafetyRuleListDTO.self, from: json)
            .items.map(SafetyRule.init(dto:))

        XCTAssertEqual(rules.map(\.weeks), [[20, 42], nil, nil])
    }
}
