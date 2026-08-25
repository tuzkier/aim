import XCTest
@testable import AimApp

@MainActor
final class SymptomPatternTests: XCTestCase {
    private func symptom(_ labels: [String], severity: Int = 2, daysAgo: Int) -> RecordItem {
        let when = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .symptom, occurredAt: when, visibility: .family, title: nil, content: nil,
            structuredData: .symptom(SymptomRecordData(
                symptoms: labels, severity: severity, note: nil)),
            attachmentRefs: [], createdAt: when, updatedAt: when)
    }

    /// 流水账看不出规律。频次视图回答的是「什么反复出现」。
    func testCountsEachSymptomAcrossRecords() {
        let patterns = SymptomPattern.make(from: [
            symptom(["腰酸"], daysAgo: 1),
            symptom(["腰酸", "恶心"], daysAgo: 3),
            symptom(["腰酸"], daysAgo: 10),
        ])

        XCTAssertEqual(patterns.first?.label, "腰酸")
        XCTAssertEqual(patterns.first?.count, 3)
    }

    func testMostFrequentComesFirst() {
        let patterns = SymptomPattern.make(from: [
            symptom(["恶心"], daysAgo: 1),
            symptom(["腰酸"], daysAgo: 2),
            symptom(["腰酸"], daysAgo: 3),
        ])

        XCTAssertEqual(patterns.map(\.label), ["腰酸", "恶心"])
    }

    /// 「最近还在不在发生」比总次数更有用——两个月前的三次和这周的三次不是一回事。
    func testTracksTheMostRecentOccurrence() {
        let patterns = SymptomPattern.make(from: [
            symptom(["腰酸"], daysAgo: 40),
            symptom(["腰酸"], daysAgo: 2),
        ])

        XCTAssertEqual(patterns.first?.daysSinceLast, 2)
    }

    /// 严重程度取记录过的最高值——最难受的那次才是要跟医生说的。
    func testKeepsTheWorstSeverity() {
        let patterns = SymptomPattern.make(from: [
            symptom(["头晕"], severity: 2, daysAgo: 1),
            symptom(["头晕"], severity: 4, daysAgo: 5),
        ])

        XCTAssertEqual(patterns.first?.worstSeverity, 4)
    }

    func testNoSymptomsMeansNoPatterns() {
        XCTAssertTrue(SymptomPattern.make(from: []).isEmpty)
    }
}
