import XCTest
@testable import AimApp

@MainActor
final class CheckupMetricInputTests: XCTestCase {
    /// 用户在文本框里输入，存的是数值。空着表示这次没测，不是 0——
    /// 当成 0 会拉平趋势线。
    func testBlankFieldsMeanNotMeasured() {
        let metrics = CheckupMetricInput(weight: "", systolic: "", diastolic: "").parsed()

        XCTAssertNil(metrics.weightKg)
        XCTAssertNil(metrics.systolic)
        XCTAssertTrue(metrics.isEmpty)
    }

    func testParsesDecimalWeight() {
        XCTAssertEqual(
            CheckupMetricInput(weight: "62.5", systolic: "", diastolic: "").parsed().weightKg, 62.5)
    }

    func testIgnoresSurroundingWhitespaceAndUnits() {
        let metrics = CheckupMetricInput(weight: " 62.5 kg ", systolic: "118", diastolic: "75").parsed()

        XCTAssertEqual(metrics.weightKg, 62.5)
        XCTAssertEqual(metrics.systolic, 118)
    }

    /// 输不进去的内容当作没填，而不是存个 0 进去。
    func testUnparseableTextIsTreatedAsNotMeasured() {
        XCTAssertNil(CheckupMetricInput(weight: "六十二", systolic: "", diastolic: "").parsed().weightKg)
    }

    /// 后端会拒收明显不可能的值，客户端先拦一道，让用户当场知道。
    func testImplausibleValuesAreReportedBeforeSaving() {
        let input = CheckupMetricInput(weight: "500", systolic: "", diastolic: "")

        XCTAssertNotNil(input.validationMessage)
        XCTAssertTrue(input.validationMessage!.contains("体重"))
    }

    func testDiastolicAboveSystolicIsReported() {
        let input = CheckupMetricInput(weight: "", systolic: "80", diastolic: "120")

        XCTAssertNotNil(input.validationMessage)
    }

    func testPlausibleValuesPassValidation() {
        XCTAssertNil(CheckupMetricInput(weight: "62.5", systolic: "118", diastolic: "75").validationMessage)
    }

    /// 只填一半血压也允许——有些产检只记了收缩压。
    func testHalfOfABloodPressureReadingIsAllowed() {
        XCTAssertNil(CheckupMetricInput(weight: "", systolic: "118", diastolic: "").validationMessage)
    }

    // MARK: - 全部 7 项

    func testAllSevenMetricsAreParsed() {
        var input = CheckupMetricInput()
        input[.weight] = "62.5"
        input[.systolic] = "118"
        input[.diastolic] = "75"
        input[.fastingGlucose] = "4.8"
        input[.hemoglobin] = "115"
        input[.fetalHeartRate] = "145"
        input[.fundalHeight] = "28"

        XCTAssertEqual(input.parsed(), CheckupMetrics(
            weightKg: 62.5, systolic: 118, diastolic: 75, fastingGlucose: 4.8,
            hemoglobin: 115, fetalHeartRate: 145, fundalHeightCm: 28))
        XCTAssertNil(input.validationMessage)
    }

    /// 范围与后端一致：胎心 100–200，宫高 10–45，血糖 2–20，血红蛋白 50–200。
    func testNewMetricsAreRangeChecked() {
        for (field, text) in [
            (CheckupMetricField.fetalHeartRate, "90"), (.fetalHeartRate, "210"),
            (.fundalHeight, "50"), (.fastingGlucose, "25"), (.hemoglobin, "30"),
        ] {
            var input = CheckupMetricInput()
            input[field] = text
            let message = input.validationMessage
            XCTAssertNotNil(message, "\(field) = \(text)")
            XCTAssertTrue(message?.contains(field.title) == true, message ?? "")
        }
        var boundary = CheckupMetricInput()
        boundary[.fetalHeartRate] = "100"
        boundary[.fundalHeight] = "45"
        XCTAssertNil(boundary.validationMessage, "边界值算在范围内")
    }

    func testFormattingDropsATrailingZero() {
        XCTAssertEqual(CheckupMetricField.format(62.0), "62")
        XCTAssertEqual(CheckupMetricField.format(62.5), "62.5")
        XCTAssertEqual(CheckupMetricField.format(0.8000000001), "0.8")
    }

    // MARK: - 其他化验项

    func testBlankOtherItemRowsAreIgnored() {
        var form = CheckupForm()
        form.hospital = "市一医院"
        form.otherItems = [CheckupOtherItemInput()]

        XCTAssertTrue(form.draft.otherItems.isEmpty)
        XCTAssertNil(form.validationMessage)
    }

    func testOtherItemNeedsANameAndAValue() {
        var form = CheckupForm()
        form.otherItems = [CheckupOtherItemInput(name: "尿蛋白")]
        XCTAssertNotNil(form.validationMessage)

        form.otherItems = [CheckupOtherItemInput(value: "+")]
        XCTAssertNotNil(form.validationMessage)

        form.otherItems = [CheckupOtherItemInput(name: " 尿蛋白 ", value: "+", unit: " ", flag: .abnormal)]
        XCTAssertNil(form.validationMessage)
        XCTAssertEqual(form.draft.otherItems, [CheckupOtherItem(name: "尿蛋白", value: "+", flag: .abnormal)])
        XCTAssertTrue(form.canSave)
    }

    func testOtherItemLengthsFollowTheBackend() {
        var form = CheckupForm()
        form.otherItems = [CheckupOtherItemInput(name: String(repeating: "长", count: 41), value: "1")]
        XCTAssertNotNil(form.validationMessage)
        form.otherItems = [CheckupOtherItemInput(name: "甲", value: "1", reference: String(repeating: "1", count: 61))]
        XCTAssertNotNil(form.validationMessage)
    }

    // MARK: - 整张表单

    /// 编辑模式回填全部字段：原样打开、原样保存，什么都不丢。
    func testEditingRoundTripsEveryField() {
        let original = CheckupRecordData(
            hospital: "市一医院", examItems: "常规产检", result: "尿蛋白弱阳性", doctorAdvice: "一周后复查",
            metrics: CheckupMetrics(
                weightKg: 60, systolic: 118, diastolic: 75, fastingGlucose: 4.8,
                hemoglobin: 112.5, fetalHeartRate: 145, fundalHeightCm: 28),
            otherItems: [
                CheckupOtherItem(name: "尿蛋白", value: "+-", unit: nil, reference: "阴性", flag: .abnormal),
                CheckupOtherItem(name: "血小板", value: "98", unit: "10^9/L", reference: "125-350", flag: .low),
            ])

        XCTAssertEqual(CheckupForm(data: original).draft, original)
    }

    /// 四段文字都可选：空白去掉后为空就是 nil。
    func testBlankTextsBecomeNil() {
        var form = CheckupForm()
        form.hospital = " 市一医院 "
        form.doctorAdvice = "  "

        XCTAssertEqual(form.draft.hospital, "市一医院")
        XCTAssertNil(form.draft.doctorAdvice)
        XCTAssertNil(form.draft.examItems)
    }

    func testAnEmptyFormCannotBeSaved() {
        XCTAssertFalse(CheckupForm().canSave)
        var form = CheckupForm()
        form.metrics[.fetalHeartRate] = "145"
        XCTAssertTrue(form.canSave, "只记了胎心也算记下了")
        form.metrics[.fetalHeartRate] = "300"
        XCTAssertFalse(form.canSave, "指标超范围不让存")
    }

    func testInvalidMetricTextCannotBeSilentlyDroppedOrRewritten() {
        for text in ["-62.5", "六十二", "62和5", "62.5.1", "60–65"] {
            var form = CheckupForm()
            form.hospital = "市一医院"
            form.metrics[.weight] = text
            XCTAssertNotNil(form.validationMessage, text)
            XCTAssertFalse(form.canSave, text)
        }
    }

    func testEditingDoesNotRoundTheStoredMetric() {
        let original = CheckupRecordData(
            hospital: nil, examItems: nil, result: nil, doctorAdvice: nil,
            metrics: CheckupMetrics(fastingGlucose: 4.856, fundalHeightCm: 28.125))
        XCTAssertEqual(CheckupForm(data: original).draft, original)
    }

    func testPhotosAloneCanBeSavedButDoNotBypassValidation() {
        var form = CheckupForm()
        XCTAssertTrue(form.canSave(photoCount: 1))
        XCTAssertFalse(form.canSave(photoCount: 0))
        form.metrics[.fetalHeartRate] = "300"
        XCTAssertFalse(form.canSave(photoCount: 1))
    }
}
