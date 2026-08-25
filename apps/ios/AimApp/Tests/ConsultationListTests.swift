import XCTest
@testable import AimApp

@MainActor
final class ConsultationListTests: XCTestCase {
    private func question(_ text: String, answered: Bool, daysAgo: Int = 0) -> RecordItem {
        let when = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .question, occurredAt: when, visibility: .family, title: nil, content: text,
            structuredData: .question(QuestionRecordData(answered: answered, answer: nil)),
            attachmentRefs: [], createdAt: when, updatedAt: when)
    }

    /// 清单只装还没问的。问过的带去只会浪费医生时间。
    func testOnlyUnansweredQuestionsMakeTheList() {
        let snapshot = LibrarySnapshot(records: [
            question("能继续游泳吗", answered: false, daysAgo: 3),
            question("要补钙吗", answered: true, daysAgo: 5),
            question("这个胎动正常吗", answered: false, daysAgo: 1),
        ])

        let list = ConsultationList.make(from: snapshot)

        XCTAssertEqual(list?.questions.count, 2)
        XCTAssertFalse(list!.questions.contains { $0.text == "要补钙吗" })
    }

    /// 按攒下来的先后排，先想到的先问——医生时间有限，别把最早的问题挤掉。
    func testQuestionsKeepTheOrderTheyWereCollected() {
        let snapshot = LibrarySnapshot(records: [
            question("后想到的", answered: false, daysAgo: 1),
            question("先想到的", answered: false, daysAgo: 9),
        ])

        XCTAssertEqual(
            ConsultationList.make(from: snapshot)?.questions.map(\.text),
            ["先想到的", "后想到的"])
    }

    func testNoPendingQuestionsMeansNoList() {
        let snapshot = LibrarySnapshot(records: [question("问过了", answered: true)])

        XCTAssertNil(ConsultationList.make(from: snapshot))
    }

    /// 复制出去的文本要能直接发给家人或给医生看，所以带编号。
    func testPlainTextIsNumberedAndReadable() {
        let snapshot = LibrarySnapshot(records: [
            question("能继续游泳吗", answered: false, daysAgo: 2),
            question("这个胎动正常吗", answered: false, daysAgo: 1),
        ])

        let text = ConsultationList.make(from: snapshot)!.plainText

        XCTAssertTrue(text.contains("1. 能继续游泳吗"))
        XCTAssertTrue(text.contains("2. 这个胎动正常吗"))
    }

    /// 问诊结束后一次性标记，而不是逐条点——那正是现在缺的一步。
    func testTheListKnowsWhichRecordsToMarkAnswered() {
        let first = question("一", answered: false, daysAgo: 2)
        let second = question("二", answered: false, daysAgo: 1)
        let snapshot = LibrarySnapshot(records: [first, second, question("三", answered: true)])

        XCTAssertEqual(
            Set(ConsultationList.make(from: snapshot)!.recordIDs),
            Set([first.id, second.id]))
    }
}
