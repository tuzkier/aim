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

    /// 把表单里的三项盖到原有指标上。表单管不到的指标（血糖、胎心等）原样保留——
    /// 编辑一份 AIM 建的报告时，不能因为表单没有那一栏就把它清掉。
    func merged(into original: CheckupMetrics) -> CheckupMetrics {
        var metrics = original
        let edited = parsed()
        metrics.weightKg = edited.weightKg
        metrics.systolic = edited.systolic
        metrics.diastolic = edited.diastolic
        return metrics
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

extension CheckupRecordData {
    /// 记录编辑器保存时组装的产检数据。文字段去掉首尾空白后为空就传 nil；
    /// 表单只管四段文字和三项指标，其他指标与其他化验项从原报告原样带回，编辑一次不会丢。
    static func composed(
        from original: CheckupRecordData?,
        hospital: String, examItems: String, result: String, doctorAdvice: String,
        metrics: CheckupMetricInput
    ) -> CheckupRecordData {
        CheckupRecordData(
            hospital: hospital.trimmed.nilIfEmpty, examItems: examItems.trimmed.nilIfEmpty,
            result: result.trimmed.nilIfEmpty, doctorAdvice: doctorAdvice.trimmed.nilIfEmpty,
            metrics: metrics.merged(into: original?.metrics ?? CheckupMetrics()),
            otherItems: original?.otherItems ?? [])
    }
}
