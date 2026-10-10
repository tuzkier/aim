import UIKit
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

/// 记下发出去的请求，并回一个固定的响应。
private final class CapturingProtocol: URLProtocol {
    nonisolated(unsafe) static var request: URLRequest?
    nonisolated(unsafe) static var body: Data?
    nonisolated(unsafe) static var responseBody = Data()
    nonisolated(unsafe) static var status = 201

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.request = request
        // URLSession 会把 httpBody 换成流交给 URLProtocol。
        Self.body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class AttachmentUploadTests: XCTestCase {
    private let pregnancyID = UUID()

    private func repository() -> BusinessRepository {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingProtocol.self]
        return BusinessRepository(
            environment: APIEnvironment(
                baseURL: URL(string: "http://stub.local")!,
                eveBaseURL: URL(string: "http://stub.local")!,
                bearerToken: "t", accountID: UUID(), familyID: UUID(), pregnancyID: pregnancyID),
            session: URLSession(configuration: config))
    }

    /// 上传接口收的是原始字节，靠 Content-Type 判断类型——不是 JSON，也不是 multipart。
    func testUploadPostsRawJPEGBytesAndReturnsTheAttachmentID() async throws {
        let attachmentID = UUID()
        CapturingProtocol.status = 201
        CapturingProtocol.responseBody = Data("""
        {"id":"\(attachmentID.uuidString.lowercased())","media_type":"image/jpeg","byte_size":4}
        """.utf8)
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])

        let id = try await repository().uploadAttachment(jpeg: jpeg)

        XCTAssertEqual(id, attachmentID)
        let request = try XCTUnwrap(CapturingProtocol.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/pregnancies/\(pregnancyID.uuidString)/attachments")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertEqual(CapturingProtocol.body, jpeg)
    }

    func testRejectedUploadThrows() async {
        CapturingProtocol.status = 413
        CapturingProtocol.responseBody = Data(#"{"code":"attachment.too_large"}"#.utf8)

        do {
            _ = try await repository().uploadAttachment(jpeg: Data([0xFF, 0xD8]))
            XCTFail("413 应当抛错")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 413, body: #"{"code":"attachment.too_large"}"#))
        } catch {
            XCTFail("应当是 APIError，实际：\(error)")
        }
    }

    /// 新建记录带上已上传的图片；没有图片时不发这个字段。
    func testCreateRecordCarriesAttachmentIDsOnlyWhenThereAreSome() throws {
        let photo = UUID()
        func body(_ ids: [UUID]) throws -> [String: Any] {
            let draft = RecordDraft(
                type: .checkup, occurredAt: .now, visibility: .family, title: nil, content: nil,
                structuredData: .checkup(CheckupRecordData(
                    hospital: nil, examItems: nil, result: nil, doctorAdvice: nil,
                    metrics: CheckupMetrics(weightKg: 60), otherItems: [])),
                attachmentIDs: ids)
            let data = try JSONEncoder.aim.encode(APICreateRecordDTO(draft: draft))
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        XCTAssertEqual(try body([photo])["attachment_ids"] as? [String], [photo.uuidString])
        XCTAssertNil(try body([])["attachment_ids"])
    }
}

final class ImageCompressionTests: XCTestCase {
    /// 噪点图几乎压不动，是最难压到 2 MB 以内的那种照片。
    private func noise(width: Int, height: Int) -> UIImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        arc4random_buf(&pixels, pixels.count)
        let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        return UIImage(cgImage: context.makeImage()!, scale: 1, orientation: .up)
    }

    private func pixelSize(_ data: Data) -> CGSize {
        let image = UIImage(data: data)!
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    func testLargeNoisyPhotoEndsUpUnder2MBWithLongEdgeAtMost2048() throws {
        let data = try XCTUnwrap(ImageCompression.jpegUnder2MB(noise(width: 4032, height: 3024)))

        XCTAssertLessThanOrEqual(data.count, 2 * 1024 * 1024)
        let size = pixelSize(data)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 2048)
        XCTAssertEqual(size.width / size.height, 4032.0 / 3024.0, accuracy: 0.01, "不能变形")
    }

    /// 小图不放大。
    func testSmallPhotoKeepsItsSize() throws {
        let data = try XCTUnwrap(ImageCompression.jpegUnder2MB(noise(width: 800, height: 600)))

        XCTAssertEqual(pixelSize(data), CGSize(width: 800, height: 600))
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8], "应当是 JPEG")
    }

    /// 只有几十像素的小图（截图里的二维码、裁过的局部）也要能传，而不是返回 nil。
    func testTinyImageIsStillCompressed() throws {
        let data = try XCTUnwrap(ImageCompression.jpegUnder2MB(noise(width: 100, height: 100)))

        XCTAssertEqual(pixelSize(data), CGSize(width: 100, height: 100))
    }

    /// JPEG 没有透明通道。透明的地方不填底色会变成黑的，截图类图片整张发黑。
    func testTransparentAreasBecomeWhite() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 32, y: 32, width: 32, height: 32))
        }

        let data = try XCTUnwrap(ImageCompression.jpegUnder2MB(image))
        let cgImage = try XCTUnwrap(UIImage(data: data)?.cgImage)

        let topLeft = try pixel(of: cgImage, x: 0, y: 0)
        XCTAssertGreaterThan(topLeft[0], 240)
        XCTAssertGreaterThan(topLeft[1], 240)
        XCTAssertGreaterThan(topLeft[2], 240)
        // 对照：不透明的红块仍是红的，证明读的确实是那个像素。
        let bottomRight = try pixel(of: cgImage, x: 63, y: 63)
        XCTAssertGreaterThan(bottomRight[0], 200)
        XCTAssertLessThan(bottomRight[1], 60)
    }

    /// 读 (x, y) 处的 RGB，坐标以左上角为原点。
    private func pixel(of image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        // CGContext 原点在左下：把目标像素挪到 1×1 画布上。
        context.draw(image, in: CGRect(
            x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return Array(pixel.prefix(3))
    }
}
