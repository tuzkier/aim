import XCTest
@testable import AimApp

@MainActor
final class LibraryFocusTests: XCTestCase {
    private func checkup(daysAgo: Int, metrics: CheckupMetrics) -> RecordItem {
        let when = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return RecordItem(
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

        XCTAssertNil(LibraryFocus.make(from: snapshot)?.tags.first { $0.contains("血压") })
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

    /// 提示只说「记下来、问医生」，不下判断——这是医疗内容的红线。
    func testTheBloodPressurePromptDefersToADoctor() {
        let snapshot = LibrarySnapshot(records: [
            checkup(daysAgo: 30, metrics: CheckupMetrics(systolic: 145, diastolic: 92)),
            checkup(daysAgo: 1, metrics: CheckupMetrics(systolic: 148, diastolic: 95)),
        ])

        let headline = LibraryFocus.make(from: snapshot)!.headline

        XCTAssertTrue(headline.contains("医生"))
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
}
