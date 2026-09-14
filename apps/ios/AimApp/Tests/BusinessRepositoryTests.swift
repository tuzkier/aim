import XCTest
@testable import AimApp

final class BusinessRepositoryTests: XCTestCase {
    func testTaskStatusMappingFailsClosedToUnknown() {
        XCTAssertEqual(TaskStatus(rawValue: "new-status"), .unknown)
        XCTAssertEqual(TaskStatus(rawValue: "COMPLETED"), .completed)
    }

    func testTaskStatusRecognizesBackendDoneAsCompleted() {
        // services/api's domain TaskStatus enum only has todo/scheduled/done —
        // "done" is the real wire value for a finished task, not "completed".
        XCTAssertEqual(TaskStatus(rawValue: "done"), .completed)
        XCTAssertEqual(TaskStatus(rawValue: "DONE"), .completed)
    }

    func testFamilyRoleUsesAccountIdentityNotRelationshipLabel() {
        let accountID = UUID()
        let member = FamilyMember(
            accountID: accountID, role: .father, nickname: nil, status: "active", joinedAt: nil)
        XCTAssertEqual(member.id, accountID)
        XCTAssertEqual(member.role, .father)
    }

    /// 成员列表里显示的是称呼；没填称呼时回退到身份，
    /// 否则两个「其他家人」在列表里完全一样。
    func testMemberDisplayNamePrefersTheNicknameAndFallsBackToTheRole() {
        func member(_ nickname: String?) -> FamilyMember {
            FamilyMember(
                accountID: UUID(), role: .otherCaregiver, nickname: nickname,
                status: "active", joinedAt: nil)
        }
        XCTAssertEqual(member("婆婆").displayName, "婆婆")
        XCTAssertEqual(member(nil).displayName, "其他家人")
        XCTAssertEqual(member("   ").displayName, "其他家人", "只有空格等于没填")
    }

    func testSessionResponseDecodesWithoutExposingInternalWiring() throws {
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

        let response = try JSONDecoder().decode(SessionResponse.self, from: payload)

        XCTAssertEqual(response.phone, "13800000001")
        XCTAssertEqual(response.role, .mother)
        XCTAssertEqual(response.accountID.uuidString, "11111111-1111-1111-1111-111111111111")
    }

    func testSessionResponseAllowsPregnancySetupToBeDeferred() throws {
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

        let response = try JSONDecoder().decode(SessionResponse.self, from: payload)

        XCTAssertNil(response.pregnancyID)
    }

    func testPregnancyDateCalculatorConvertsLastMenstrualPeriodToDueDate() {
        let lmp = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 4, day: 11).date!

        XCTAssertEqual(
            PregnancyDateCalculator.dueDate(fromLastMenstrualPeriod: lmp),
            DateComponents(calendar: .init(identifier: .gregorian), year: 2027, month: 1, day: 16).date!
        )
    }

    func testRecordDecoderMapsTypedSymptomStructuredData() throws {
        let record = try JSONDecoder.aim.decode(APIRecordDTO.self, from: recordPayload(
            type: "symptom",
            structuredData: #"{"symptoms":["恶心","乏力"],"severity":3,"note":"下午明显","future_field":"ignored"}"#
        ))

        XCTAssertEqual(RecordItem(dto: record).type, .symptom)
        XCTAssertEqual(RecordItem(dto: record).structuredData, .symptom(SymptomRecordData(symptoms: ["恶心", "乏力"], severity: 3, note: "下午明显")))
    }

    func testRecordDecoderMapsTypedCheckupStructuredData() throws {
        let record = try JSONDecoder.aim.decode(APIRecordDTO.self, from: recordPayload(
            type: "checkup",
            structuredData: #"{"hospital":"杭州市妇产科医院","exam_items":"NT","result":"正常","doctor_advice":"按时复诊","ignored":true}"#
        ))

        XCTAssertEqual(RecordItem(dto: record).structuredData, .checkup(CheckupRecordData(hospital: "杭州市妇产科医院", examItems: "NT", result: "正常", doctorAdvice: "按时复诊")))
    }

    func testRecordDecoderMapsUnknownTypeToUnknown() throws {
        let record = try JSONDecoder.aim.decode(APIRecordDTO.self, from: recordPayload(type: "future_type", structuredData: "{}"))

        XCTAssertEqual(RecordItem(dto: record).type, .unknown)
        XCTAssertEqual(RecordItem(dto: record).structuredData, .unknown)
    }

    func testRecordDecoderAcceptsFractionalSecondTimestamps() throws {
        let payload = Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "pregnancy_id": "22222222-2222-2222-2222-222222222222",
          "family_id": "33333333-3333-3333-3333-333333333333",
          "author_account_id": "44444444-4444-4444-4444-444444444444",
          "type": "note",
          "occurred_at": "2026-08-16T08:30:00.123456Z",
          "visibility": "family",
          "title": "复诊后记录",
          "content": "一切顺利",
          "structured_data": {},
          "attachment_refs": [],
          "created_at": "2026-08-16T08:30:00.123456Z",
          "updated_at": "2026-08-16T08:30:00.654321Z"
        }
        """.utf8)

        let record = try JSONDecoder.aim.decode(APIRecordDTO.self, from: payload)

        XCTAssertEqual(record.type, .note)
        XCTAssertEqual(record.title, "复诊后记录")
    }

    private func recordPayload(type: String, structuredData: String) -> Data {
        Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "pregnancy_id": "22222222-2222-2222-2222-222222222222",
          "family_id": "33333333-3333-3333-3333-333333333333",
          "author_account_id": "44444444-4444-4444-4444-444444444444",
          "type": "\(type)",
          "occurred_at": "2026-08-16T08:30:00Z",
          "visibility": "family",
          "title": null,
          "content": null,
          "structured_data": \(structuredData),
          "attachment_refs": [],
          "created_at": "2026-08-16T08:30:00Z",
          "updated_at": "2026-08-16T08:30:00Z"
        }
        """.utf8)
    }

    func testCreateTaskBodyUsesSnakeCaseAndOmitsNothingRequired() throws {
        let memberID = UUID()
        let due = Date(timeIntervalSince1970: 1_790_000_000)
        let body = CreateTaskBody(title: "买叶酸", description: "药店", dueAt: due, assignedMemberID: memberID, recordID: nil, sourceType: nil)
        let data = try JSONEncoder.aim.encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["title"] as? String, "买叶酸")
        XCTAssertEqual(json["description"] as? String, "药店")
        XCTAssertEqual(json["assigned_member_id"] as? String, memberID.uuidString)
        XCTAssertNotNil(json["due_at"])
        XCTAssertNil(json["record_id"], "手动新建不带记录")
        XCTAssertNil(json["source_type"], "留给服务端默认的 user")
    }

    func testCreateTaskFromRecordBodyKeepsRecordSource() throws {
        let recordID = UUID()
        let body = CreateTaskBody(title: "复查", description: nil, dueAt: nil, assignedMemberID: nil, recordID: recordID, sourceType: "record")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.aim.encode(body)) as? [String: Any])
        XCTAssertEqual(json["record_id"] as? String, recordID.uuidString)
        XCTAssertEqual(json["source_type"] as? String, "record")
    }
}

final class TaskActorMappingTests: XCTestCase {
    func testAgentActorRawValueMapsToAgent() {
        XCTAssertEqual(TaskActor(rawValue: "agent"), .agent)
        XCTAssertEqual(TaskActor(rawValue: "AGENT"), .agent)
    }

    func testAccountAndSystemActorsAreNotAgentChanged() {
        XCTAssertFalse(TaskActor.account.isAgent)
        XCTAssertFalse(TaskActor.system.isAgent)
        XCTAssertTrue(TaskActor.agent.isAgent)
    }

    func testUnrecognisedActorFallsBackToUnknown() {
        XCTAssertEqual(TaskActor(rawValue: "robot"), .unknown)
        XCTAssertFalse(TaskActor.unknown.isAgent)
    }
}
