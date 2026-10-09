import XCTest
@testable import AimApp

final class EncyclopediaCatalogTests: XCTestCase {
    private func summary(_ id: String, weeks: [Int]?, pick: Bool = true) -> EncyclopediaEntrySummary {
        EncyclopediaEntrySummary(
            id: id, topic: String(id.split(separator: ".")[0]), title: id,
            aliases: [], weeks: weeks, summary: "摘要", pick: pick)
    }

    private var catalog: EncyclopediaCatalog {
        EncyclopediaCatalog(
            topics: [EncyclopediaTopic(id: "body", name: "身体变化与不适", count: 4)],
            entries: [
                summary("body.early", weeks: [4, 12]),
                summary("body.mid", weeks: [20, 30]),
                summary("body.always", weeks: nil),
                summary("body.now", weeks: [24, 28]),
            ])
    }

    /// 全程适用的条目每周都会出现，放进「这周读什么」等于没推荐。
    func testWeeklyPicksSkipWholePregnancyEntriesAndRankByClosestStart() {
        XCTAssertEqual(catalog.picks(forWeek: 25).map(\.id), ["body.now", "body.mid"])
        XCTAssertEqual(catalog.picks(forWeek: 25, limit: 1).map(\.id), ["body.now"])
        XCTAssertEqual(catalog.picks(forWeek: 40).map(\.id), [])
    }

    /// 只针对部分人群的条目（如羊水穿刺）不进首页推荐，但主题页和本周计数照常算它。
    func testEntriesMarkedNotForPicksStayOutOfPicksButRemainInTopicPage() {
        let catalog = EncyclopediaCatalog(
            topics: [EncyclopediaTopic(id: "checkup", name: "产检项目", count: 2)],
            entries: [
                summary("checkup.amnio", weeks: [16, 22], pick: false),
                summary("checkup.screening", weeks: [15, 20]),
            ])

        XCTAssertEqual(catalog.picks(forWeek: 16).map(\.id), ["checkup.screening"])
        XCTAssertEqual(
            catalog.entries(inTopic: "checkup", week: 16).map(\.id),
            ["checkup.amnio", "checkup.screening"])
        XCTAssertEqual(catalog.timelyCount(topic: "checkup", week: 16), 2)
    }

    func testTopicPageListsTimelyEntriesFirstThenKeepsFileOrder() {
        XCTAssertEqual(
            catalog.entries(inTopic: "body", week: 25).map(\.id),
            ["body.mid", "body.now", "body.early", "body.always"])
        XCTAssertEqual(
            catalog.entries(inTopic: "body", week: nil).map(\.id),
            ["body.early", "body.mid", "body.always", "body.now"])
    }

    func testTimelyCountIgnoresWholePregnancyEntries() {
        XCTAssertEqual(catalog.timelyCount(topic: "body", week: 25), 2)
        XCTAssertEqual(catalog.timelyCount(topic: "body", week: nil), 0)
    }

    func testWeeksLabel() {
        XCTAssertEqual(summary("a.b", weeks: [24, 28]).weeksLabel, "孕 24–28 周")
        XCTAssertEqual(summary("a.b", weeks: [12, 12]).weeksLabel, "孕 12 周")
        XCTAssertNil(summary("a.b", weeks: nil).weeksLabel)
    }

    func testDecodesEntryDetailFromTheAPIShape() throws {
        let json = """
        {"id":"paperwork.allowance","topic":"paperwork","title":"生育津贴","aliases":[],
         "weeks":null,"summary":"摘要","sections":[{"heading":"去哪办","text":"正文"}],
         "ask":["要带什么材料","多久能到账"],"related":[{"id":"paperwork.leave","title":"产假"}],
         "kind":"policy","link":"https://example.com","source":"来源",
         "source_url":"https://example.com","reviewed_at":null,"review_status":"draft"}
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(EncyclopediaEntry.self, from: json)

        XCTAssertTrue(entry.isPolicy)
        XCTAssertTrue(entry.isDraft)
        XCTAssertEqual(entry.related.first?.title, "产假")
        XCTAssertEqual(entry.sections.first?.heading, "去哪办")
        XCTAssertNil(entry.weeksLabel)
    }

    func testDecodesCatalogFromTheAPIShape() throws {
        let json = """
        {"topics":[{"id":"diet","name":"饮食营养","count":1}],
         "entries":[{"id":"diet.iron","topic":"diet","title":"补铁","aliases":["贫血"],"weeks":[13,40],"summary":"摘要"}]}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(EncyclopediaCatalog.self, from: json)

        XCTAssertEqual(decoded.topics.first?.icon, "fork.knife")
        XCTAssertEqual(decoded.entries.first?.weeks, [13, 40])
        // 旧版服务端不带 pick：缺省可以进推荐。
        XCTAssertEqual(decoded.entries.first?.pick, true)
    }

    func testDecodesPickFlagWhenPresent() throws {
        let json = """
        {"topics":[],"entries":[
          {"id":"checkup.amnio","topic":"checkup","title":"羊水穿刺","aliases":[],"weeks":[16,22],"summary":"摘要","pick":false},
          {"id":"checkup.nt","topic":"checkup","title":"NT","aliases":[],"weeks":[11,14],"summary":"摘要","pick":true}]}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(EncyclopediaCatalog.self, from: json)

        XCTAssertEqual(decoded.entries.map(\.pick), [false, true])
    }
}
