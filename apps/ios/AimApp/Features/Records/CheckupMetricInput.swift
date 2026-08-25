import Foundation

/// 产检指标的文本输入。
///
/// 界面上是文本框，存下去是数值。空着表示这次没测——不是 0，
/// 当成 0 会把趋势线拉平。
struct CheckupMetricInput: Equatable, Sendable {
    var weight: String = ""
    var systolic: String = ""
    var diastolic: String = ""

    func parsed() -> CheckupMetrics {
        CheckupMetrics(
            weightKg: Self.number(weight),
            systolic: Self.number(systolic),
            diastolic: Self.number(diastolic)
        )
    }

    /// 后端会拒收明显不可能的值，客户端先拦一道，让用户当场知道
    /// 而不是保存失败后猜原因。范围与后端保持一致。
    var validationMessage: String? {
        let metrics = parsed()
        if let weight = metrics.weightKg, !(30...200).contains(weight) {
            return "体重看起来不太对，请确认单位是千克。"
        }
        if let systolic = metrics.systolic, !(60...250).contains(systolic) {
            return "收缩压超出了常见范围，请确认。"
        }
        if let diastolic = metrics.diastolic, !(30...150).contains(diastolic) {
            return "舒张压超出了常见范围，请确认。"
        }
        if let systolic = metrics.systolic, let diastolic = metrics.diastolic,
           diastolic >= systolic {
            return "舒张压应当低于收缩压，可能填反了。"
        }
        return nil
    }

    /// 容忍用户顺手带上的单位与空格。解析不出来就当没填，
    /// 而不是存个 0 进去。
    private static func number(_ text: String) -> Double? {
        let digits = text.filter { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, let value = Double(digits) else { return nil }
        return value
    }
}
