import XCTest
@testable import AimApp

final class HospitalTripTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let me = UUID(), partner = UUID()

    private func trip(author: UUID, hoursAgo: Double, reason: HospitalTripReason = .contractions,
                      note: String? = nil) -> RecordItem {
        let at = now.addingTimeInterval(-hoursAgo * 3600)
        return RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: author,
            type: .hospitalTrip, occurredAt: at, visibility: .family, title: HospitalTrip.title,
            content: note, structuredData: .hospitalTrip(HospitalTripRecordData(reason: reason)),
            attachmentRefs: [], createdAt: at, updatedAt: at)
    }

    func testDraftIsAlwaysFamilyVisibleWithTrimmedNote() {
        let linked = UUID()
        let draft = HospitalTrip.draft(reason: .waterBroke, note: "  打车去市妇保 \n", contractionRecordID: linked, at: now)
        XCTAssertEqual(draft.type, .hospitalTrip)
        XCTAssertEqual(draft.visibility, .family)
        XCTAssertEqual(draft.title, "我们出发去医院了")
        XCTAssertEqual(draft.content, "打车去市妇保")
        XCTAssertEqual(draft.structuredData, .hospitalTrip(HospitalTripRecordData(reason: .waterBroke, contractionRecordID: linked)))
        XCTAssertNil(HospitalTrip.draft(reason: .other, note: "   ", contractionRecordID: nil, at: now).content)
    }

    func testBannerPicksTheLatestWithin24Hours() {
        let old = trip(author: partner, hoursAgo: 25)
        let recent = trip(author: partner, hoursAgo: 2)
        let newest = trip(author: partner, hoursAgo: 1)
        XCTAssertEqual(HospitalTrip.banner(in: [old, recent, newest], now: now, me: me, dismissed: [])?.id, newest.id)
        XCTAssertNil(HospitalTrip.banner(in: [old], now: now, me: me, dismissed: []))
    }

    func testOthersCanDismissButTheAuthorAlwaysSeesTheirOwn() {
        let mine = trip(author: me, hoursAgo: 1)
        let theirs = trip(author: partner, hoursAgo: 1)
        XCTAssertNil(HospitalTrip.banner(in: [theirs], now: now, me: me, dismissed: [theirs.id]))
        XCTAssertEqual(HospitalTrip.banner(in: [mine], now: now, me: me, dismissed: [mine.id])?.id, mine.id,
                       "作者看到的是「撤回」，不会被「知道了」藏掉")
    }

    func testBannerText() {
        let record = trip(author: partner, hoursAgo: 1, reason: .waterBroke)
        let time = record.occurredAt.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(HospitalTrip.bannerText(record, actorName: "妈妈"), "妈妈 \(time) 出发去医院了 · 破水")
        let withNote = trip(author: partner, hoursAgo: 1, note: "爸爸陪着")
        XCTAssertTrue(HospitalTrip.bannerText(withNote, actorName: "妈妈").hasSuffix("· 爸爸陪着"))
    }

    func testDismissalsPersist() {
        let defaults = UserDefaults(suiteName: "HospitalTripTests.\(UUID().uuidString)")!
        let id = UUID()
        HospitalTripDismissals(defaults: defaults).dismiss(id)
        XCTAssertEqual(HospitalTripDismissals(defaults: defaults).ids, [id])
    }
}
