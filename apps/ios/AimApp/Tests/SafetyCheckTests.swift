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
}
