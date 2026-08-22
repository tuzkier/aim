import Foundation
import Observation

/// 孕期日期录入的选择状态。
///
/// `selectedDate` 刻意是可选的：没有主动选过日期就不能提交。早期实现给它预填了
/// 「今天 + 154 天」，而 280 − 154 = 126 天正好是孕 18 周，也正好是内容库里唯一
/// 有完整任务的那一周——于是「不看日期直接保存」会得到一份看起来很像样的假档案。
/// 预产期是医疗相关数据，宁可挡住提交，也不替用户猜。
@MainActor
@Observable
final class PregnancySetupModel {
    var dateMode: PregnancyDateMode = .dueDate
    var selectedDate: Date?
    var isPickingDate = false
    var isSubmitting = false
    var errorMessage: String?

    var canSave: Bool { selectedDate != nil && !isSubmitting }

    /// 展开日期选择器。选择器必须绑定一个非可选 `Date` 才能渲染，
    /// 见 `displayAnchor`——但那只是落点，滚轮真的动过 `selectedDate` 才有值。
    func beginPickingDate() {
        isPickingDate = true
    }

    /// 选择器初次展开时停在哪一天。取当前模式允许范围的边界：预产期取最早
    /// （今天），末次月经取最晚（今天）。刻意用边界值，让它看起来就不像
    /// 一个「替你填好的答案」。
    var displayAnchor: Date {
        switch dateMode {
        case .dueDate: dateMode.dateRange.lowerBound
        case .lastMenstrualPeriod: dateMode.dateRange.upperBound
        }
    }

    /// 无论用户选的是预产期还是末次月经，提交给后端的一律是预产期。
    var resolvedDueDate: Date? {
        selectedDate.map { dateMode.dueDate(from: $0) }
    }

    /// 切换「预产期 / 末次月经」时把已选日期按 280 天换算过去。
    /// 还没选过就保持未选择——不能因为切了个模式就凭空冒出一个日期。
    func modeDidChange(to mode: PregnancyDateMode) {
        dateMode = mode
        guard let current = selectedDate else { return }
        selectedDate = switch mode {
        case .lastMenstrualPeriod:
            PregnancyDateCalculator.lastMenstrualPeriod(fromDueDate: current)
        case .dueDate:
            PregnancyDateCalculator.dueDate(fromLastMenstrualPeriod: current)
        }
    }
}
