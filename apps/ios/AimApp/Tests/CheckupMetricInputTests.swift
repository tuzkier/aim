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
}
