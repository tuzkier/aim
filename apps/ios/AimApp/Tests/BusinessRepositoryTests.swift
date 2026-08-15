import XCTest
@testable import AimApp

final class BusinessRepositoryTests: XCTestCase {
    func testTaskStatusMappingFailsClosedToUnknown() {
        XCTAssertEqual(TaskStatus(rawValue: "new-status"), .unknown)
        XCTAssertEqual(TaskStatus(rawValue: "COMPLETED"), .completed)
    }

    func testFamilyRoleUsesAccountIdentityNotRelationshipLabel() {
        let accountID = UUID()
        let member = FamilyMember(accountID: accountID, role: .father, status: "active", joinedAt: nil)
        XCTAssertEqual(member.id, accountID)
        XCTAssertEqual(member.role, .father)
    }

    func testDemoSessionResponseDecodesWithoutExposingInternalWiring() throws {
        let payload = """
        {
          "account_id": "11111111-1111-1111-1111-111111111111",
          "phone": "13800000001",
          "family_id": "22222222-2222-2222-2222-222222222222",
          "pregnancy_id": "33333333-3333-3333-3333-333333333333",
          "role": "mother",
          "token": "aim.v1.demo"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DemoSessionResponse.self, from: payload)

        XCTAssertEqual(response.phone, "13800000001")
        XCTAssertEqual(response.role, .mother)
        XCTAssertEqual(response.accountID.uuidString, "11111111-1111-1111-1111-111111111111")
    }

    func testDemoSessionResponseAllowsPregnancySetupToBeDeferred() throws {
        let payload = """
        {
          "account_id": "11111111-1111-1111-1111-111111111111",
          "phone": "13900000001",
          "family_id": "22222222-2222-2222-2222-222222222222",
          "pregnancy_id": null,
          "role": "mother",
          "token": "aim.v1.demo"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DemoSessionResponse.self, from: payload)

        XCTAssertNil(response.pregnancyID)
    }

    func testPregnancyDateCalculatorConvertsLastMenstrualPeriodToDueDate() {
        let lmp = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 4, day: 11).date!

        XCTAssertEqual(
            PregnancyDateCalculator.dueDate(fromLastMenstrualPeriod: lmp),
            DateComponents(calendar: .init(identifier: .gregorian), year: 2027, month: 1, day: 16).date!
        )
    }
}
