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
}
