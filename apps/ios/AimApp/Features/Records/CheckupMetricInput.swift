import Foundation

/// 白名单里的 7 项产检指标。表单、报告详情的对比都按这个顺序排。
/// 范围与后端 `CHECKUP_METRIC_RANGES` 一致——只挡明显的输入错误，不判断正常与否。
enum CheckupMetricField: String, CaseIterable, Identifiable, Sendable {
    case weight
    case systolic
    case diastolic
    case fastingGlucose
    case hemoglobin
    case fetalHeartRate
    case fundalHeight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: "体重"
        case .systolic: "收缩压"
        case .diastolic: "舒张压"
        case .fastingGlucose: "空腹血糖"
        case .hemoglobin: "血红蛋白"
        case .fetalHeartRate: "胎心"
        case .fundalHeight: "宫高"
        }
    }

    var unit: String {
        switch self {
        case .weight: "kg"
        case .systolic, .diastolic: "mmHg"
        case .fastingGlucose: "mmol/L"
        case .hemoglobin: "g/L"
        case .fetalHeartRate: "次/分"
        case .fundalHeight: "cm"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .weight: 30...200
        case .systolic: 60...250
        case .diastolic: 30...150
        case .fastingGlucose: 2...20
        case .hemoglobin: 50...200
        case .fetalHeartRate: 100...200
        case .fundalHeight: 10...45
        }
    }

    var keyPath: WritableKeyPath<CheckupMetrics, Double?> {
        switch self {
        case .weight: \.weightKg
        case .systolic: \.systolic
        case .diastolic: \.diastolic
        case .fastingGlucose: \.fastingGlucose
        case .hemoglobin: \.hemoglobin
        case .fetalHeartRate: \.fetalHeartRate
        case .fundalHeight: \.fundalHeightCm
        }
    }

    fileprivate var outOfRangeMessage: String {
        switch self {
        case .weight: "体重看起来不太对，请确认单位是千克。"
        case .systolic: "收缩压超出了常见范围，请确认。"
        case .diastolic: "舒张压超出了常见范围，请确认。"
        default:
            "\(title)超出了常见范围（\(Self.format(range.lowerBound))–\(Self.format(range.upperBound)) \(unit)），请确认。"
        }
    }

    /// 62.0 显示成「62」，0.8000001 显示成「0.8」：最多两位小数，去掉末尾的 0。
    /// 编辑回填也用它，两位足够保住化验单上的读数（如血糖 4.85）。
    static func format(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }
}

/// 产检指标的文本输入。
///
/// 界面上是文本框，存下去是数值。空着表示这次没测——不是 0，
/// 当成 0 会把趋势线拉平。
struct CheckupMetricInput: Equatable, Sendable {
    private var texts: [CheckupMetricField: String] = [:]

    init(weight: String = "", systolic: String = "", diastolic: String = "") {
        texts = [.weight: weight, .systolic: systolic, .diastolic: diastolic]
    }

    /// 编辑时回填：7 项都带回来。
    init(metrics: CheckupMetrics) {
        for field in CheckupMetricField.allCases {
            // 回填保留存下的精度；详情页的两位小数格式只用于展示。
            if let value = metrics[keyPath: field.keyPath] { texts[field] = String(value) }
        }
    }

    subscript(field: CheckupMetricField) -> String {
        get { texts[field] ?? "" }
        set { texts[field] = newValue }
    }

    var weight: String { self[.weight] }
    var systolic: String { self[.systolic] }
    var diastolic: String { self[.diastolic] }

    func parsed() -> CheckupMetrics {
        var metrics = CheckupMetrics()
        for field in CheckupMetricField.allCases {
            metrics[keyPath: field.keyPath] = Self.number(self[field], unit: field.unit)
        }
        return metrics
    }

    /// 后端会拒收明显不可能的值，客户端先拦一道，让用户当场知道
    /// 而不是保存失败后猜原因。范围与后端保持一致。
    var validationMessage: String? {
        let metrics = parsed()
        for field in CheckupMetricField.allCases {
            if !self[field].trimmed.isEmpty, metrics[keyPath: field.keyPath] == nil {
                return "\(field.title)请填一个数值，单位是 \(field.unit)。"
            }
            if let value = metrics[keyPath: field.keyPath], !field.range.contains(value) {
                return field.outOfRangeMessage
            }
        }
        if let systolic = metrics.systolic, let diastolic = metrics.diastolic,
           diastolic >= systolic {
            return "舒张压应当低于收缩压，可能填反了。"
        }
        return nil
    }

    /// 只去掉两侧空白和本项单位，保留负号；不能把「60–65」拼成另一个读数。
    private static func number(_ text: String, unit: String) -> Double? {
        var number = text.trimmed
        if number.hasSuffix(unit) { number = String(number.dropLast(unit.count)).trimmed }
        guard let value = Double(number), value.isFinite else { return nil }
        return value
    }
}

/// 表单里的一行「其他化验项」。数值按化验单原样填文字（「+」「阴性」「5.2」）。
struct CheckupOtherItemInput: Identifiable, Equatable, Sendable {
    let id = UUID()
    var name = ""
    var value = ""
    var unit = ""
    var reference = ""
    var flag: CheckupFlag?

    init(name: String = "", value: String = "", unit: String = "", reference: String = "", flag: CheckupFlag? = nil) {
        self.name = name
        self.value = value
        self.unit = unit
        self.reference = reference
        self.flag = flag
    }

    init(item: CheckupOtherItem) {
        self.init(name: item.name, value: item.value, unit: item.unit ?? "",
                  reference: item.reference ?? "", flag: item.flag)
    }

    /// 什么都没填的行：保存时跳过，不算错。点了「加一项」又不填很常见。
    var isBlank: Bool {
        [name, value, unit, reference].allSatisfy { $0.trimmed.isEmpty } && flag == nil
    }

    var item: CheckupOtherItem? {
        guard !isBlank else { return nil }
        return CheckupOtherItem(
            name: name.trimmed, value: value.trimmed, unit: unit.trimmed.nilIfEmpty,
            reference: reference.trimmed.nilIfEmpty, flag: flag)
    }

    /// 长度上限与后端一致：名称、数值 40 字，单位 20 字，参考范围 60 字。
    var validationMessage: String? {
        guard !isBlank else { return nil }
        if name.trimmed.isEmpty { return "化验项要填名称。" }
        if value.trimmed.isEmpty { return "「\(name.trimmed)」要填数值或结果，比如「阴性」「5.2」。" }
        if name.trimmed.count > 40 || value.trimmed.count > 40 { return "化验项的名称和数值各不超过 40 个字。" }
        if unit.trimmed.count > 20 { return "「\(name.trimmed)」的单位不超过 20 个字。" }
        if reference.trimmed.count > 60 { return "「\(name.trimmed)」的参考范围不超过 60 个字。" }
        return nil
    }
}

/// 产检报告表单的全部内容。新建与编辑共用；编辑时用原报告回填，保存出来的和打开时一样。
struct CheckupForm: Equatable, Sendable {
    static let maxOtherItems = 60

    var hospital = ""
    var examItems = ""
    var result = ""
    var doctorAdvice = ""
    var metrics = CheckupMetricInput()
    var otherItems: [CheckupOtherItemInput] = []

    init(suggestedExamItems: String? = nil) {
        examItems = suggestedExamItems ?? ""
    }

    init(data: CheckupRecordData) {
        hospital = data.hospital ?? ""
        examItems = data.examItems ?? ""
        result = data.result ?? ""
        doctorAdvice = data.doctorAdvice ?? ""
        metrics = CheckupMetricInput(metrics: data.metrics)
        otherItems = data.otherItems.map(CheckupOtherItemInput.init(item:))
    }

    /// 文字段去掉首尾空白后为空就传 nil；空行化验项跳过。
    var draft: CheckupRecordData {
        CheckupRecordData(
            hospital: hospital.trimmed.nilIfEmpty, examItems: examItems.trimmed.nilIfEmpty,
            result: result.trimmed.nilIfEmpty, doctorAdvice: doctorAdvice.trimmed.nilIfEmpty,
            metrics: metrics.parsed(),
            otherItems: otherItems.compactMap(\.item))
    }

    var validationMessage: String? {
        if let message = metrics.validationMessage { return message }
        if let message = otherItems.lazy.compactMap(\.validationMessage).first { return message }
        if otherItems.filter({ !$0.isBlank }).count > Self.maxOtherItems {
            return "其他化验项最多 \(Self.maxOtherItems) 项。"
        }
        return nil
    }

    /// 四段文字都可选，但总得记下点什么；填错了的不让存——后端也会拒，不如当场说清楚。
    var canSave: Bool { canSave(photoCount: 0) }

    func canSave(photoCount: Int) -> Bool {
        (!draft.isBlank || photoCount > 0) && validationMessage == nil
    }
}
