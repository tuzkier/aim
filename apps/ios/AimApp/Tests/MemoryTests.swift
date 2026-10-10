import XCTest
@testable import AimApp

@MainActor
final class MemoryTests: XCTestCase {
    func testMemoryRoundTripPreservesKindAndText() throws {
        for kind in MemoryKind.supported {
            let original = RecordStructuredData.memory(MemoryRecordData(kind: kind, text: "以后回答请简短"))
            let encoded = try JSONEncoder.aim.encode(APIRecordStructuredDataDTO(recordData: original))
            let decoded = try JSONDecoder.aim.decode(APIRecordStructuredDataDTO.self, from: encoded)
            XCTAssertEqual(decoded.recordData(for: .memory), original)
        }
    }

    func testUnknownMemoryKindDoesNotLoseTheFactOrSaveItAsAnotherKind() throws {
        let bytes = Data(#"{"kind":"future_kind","text":"已有事实"}"#.utf8)
        let dto = try JSONDecoder.aim.decode(APIRecordStructuredDataDTO.self, from: bytes)
        guard case let .memory(data) = dto.recordData(for: .memory) else { return XCTFail() }
        XCTAssertEqual(data.text, "已有事实")
        XCTAssertEqual(data.kind, .unknown)
        var form = MemoryForm()
        form.kind = .unknown
        form.text = data.text
        XCTAssertFalse(form.canSave)
    }

    func testMemoryFormRejectsBlankAndTooLongFacts() {
        var form = MemoryForm()
        form.text = "   "
        XCTAssertFalse(form.canSave)
        form.text = String(repeating: "字", count: 80)
        XCTAssertTrue(form.canSave)
        form.text += "字"
        XCTAssertFalse(form.canSave)
    }

    func testEditingPreservesPrivateVisibilityAndDateAndNormalizesText() {
        let record = RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: .memory, occurredAt: .distantPast, visibility: .private, title: "短答", content: nil,
            structuredData: .memory(MemoryRecordData(kind: .preference, text: "短答")),
            attachmentRefs: [], createdAt: .now, updatedAt: .now)
        var form = MemoryForm(record: record)
        form.text = "  回答详细一点  "
        let draft = form.draft(record: record)
        XCTAssertEqual(draft.visibility, .private)
        XCTAssertEqual(draft.occurredAt, record.occurredAt)
        XCTAssertEqual(draft.structuredData, .memory(MemoryRecordData(kind: .preference, text: "回答详细一点")))
        XCTAssertEqual(draft.title, "回答详细一点")
        XCTAssertFalse(RecordType.memory.canEditInComposer)
    }

    func testMemoryCardCountsOnlyMemoryRecords() {
        XCTAssertEqual(LibraryCategoryID.memories.summary(from: LibrarySnapshot()).headline, "把重要的事告诉 AIM")
        XCTAssertTrue(LibraryCatalog.gridCategories.contains { $0.id == .memories })
    }
}
