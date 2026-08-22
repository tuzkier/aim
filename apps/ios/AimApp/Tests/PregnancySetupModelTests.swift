import XCTest
@testable import AimApp

@MainActor
final class PregnancySetupModelTests: XCTestCase {
    private let calendar = PregnancyDateCalculator.calendar

    /// 核心约束：不主动选日期就不能提交。原实现预填「今天 + 154 天」，
    /// 正好落在孕 18 周——也正好是内容库里唯一有完整任务的那一周，
    /// 于是「不看日期直接保存」会得到一份看起来很像样的假档案。
    func testCannotSaveBeforeChoosingADate() {
        let model = PregnancySetupModel()

        XCTAssertNil(model.selectedDate)
        XCTAssertFalse(model.canSave)
    }

    /// 展开选择器 ≠ 选好了日期。选择器必须先显示一个落点日期才能渲染，
    /// 但那个落点不能算数——否则「点开就能保存」，等于把默认值挪深了一层。
    func testRevealingThePickerIsNotAChoice() {
        let model = PregnancySetupModel()

        model.beginPickingDate()

        XCTAssertTrue(model.isPickingDate)
        XCTAssertNil(model.selectedDate)
        XCTAssertFalse(model.canSave)
    }

    func testCanSaveOnceDateChosen() {
        let model = PregnancySetupModel()
        model.selectedDate = calendar.date(byAdding: .day, value: 120, to: .now)

        XCTAssertTrue(model.canSave)
    }

    func testSubmittingBlocksSaveEvenWithDateChosen() {
        let model = PregnancySetupModel()
        model.selectedDate = calendar.date(byAdding: .day, value: 120, to: .now)
        model.isSubmitting = true

        XCTAssertFalse(model.canSave)
    }

    /// 切换「预产期 / 末次月经」时已选的日期要跟着换算，而不是丢失或原样保留。
    func testSwitchingModeConvertsChosenDateBy280Days() {
        let model = PregnancySetupModel()
        let due = calendar.date(from: DateComponents(year: 2027, month: 1, day: 15))!
        model.selectedDate = due

        model.dateMode = .lastMenstrualPeriod
        model.modeDidChange(to: .lastMenstrualPeriod)

        let expected = calendar.date(byAdding: .day, value: -280, to: due)!
        XCTAssertEqual(
            calendar.startOfDay(for: model.selectedDate!),
            calendar.startOfDay(for: expected)
        )
    }

    /// 还没选就切换模式，不能凭空冒出一个日期——那正是原来的缺陷。
    func testSwitchingModeKeepsSelectionEmptyWhenNothingChosen() {
        let model = PregnancySetupModel()

        model.dateMode = .lastMenstrualPeriod
        model.modeDidChange(to: .lastMenstrualPeriod)

        XCTAssertNil(model.selectedDate)
        XCTAssertFalse(model.canSave)
    }

    func testResolvedDueDateConvertsFromLastMenstrualPeriod() {
        let model = PregnancySetupModel()
        let lmp = calendar.date(from: DateComponents(year: 2026, month: 4, day: 10))!
        model.dateMode = .lastMenstrualPeriod
        model.selectedDate = lmp

        let expected = calendar.date(byAdding: .day, value: 280, to: lmp)!
        XCTAssertEqual(
            calendar.startOfDay(for: model.resolvedDueDate!),
            calendar.startOfDay(for: expected)
        )
    }

    func testResolvedDueDateIsNilWithoutSelection() {
        XCTAssertNil(PregnancySetupModel().resolvedDueDate)
    }
}
