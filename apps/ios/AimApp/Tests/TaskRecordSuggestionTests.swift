import XCTest
@testable import AimApp

final class TaskRecordSuggestionTests: XCTestCase {
    func testChecklistKeywordsMapToCheckup() {
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: "预约下周的系统超声检查"), .checkup)
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: "整理最近一次产检记录"), .checkup)
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: "去医院做糖耐测试"), .checkup)
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: "四维彩超预约"), .checkup)
    }

    func testUnrelatedTitlesMapToNote() {
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: "晚饭后散步 20 分钟"), .note)
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: "确认杭州生育待遇材料"), .note)
    }

    func testEmptyTitleFallsBackToNote() {
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: ""), .note)
    }
}
