import Foundation

/// 孕期百科：经人工审核、随内容发布的孕期知识，按主题与孕周组织。
/// 目录一次整份拉取（约 60 条摘要），挑选与排序在本地做；正文按需拉取。
struct EncyclopediaTopic: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let count: Int

    /// 图标是客户端的事，服务端只给主题编号。
    var icon: String {
        switch id {
        case "checkup": "stethoscope"
        case "body": "figure.stand"
        case "diet": "fork.knife"
        case "life": "figure.walk"
        case "birth": "suitcase"
        case "paperwork": "doc.text"
        default: "book"
        }
    }
}

func encyclopediaWeeksLabel(_ weeks: [Int]?) -> String? {
    guard let weeks, weeks.count == 2 else { return nil }
    return weeks[0] == weeks[1] ? "孕 \(weeks[0]) 周" : "孕 \(weeks[0])–\(weeks[1]) 周"
}

struct EncyclopediaEntrySummary: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let topic: String
    let title: String
    let aliases: [String]
    /// `[起, 止]`；`nil` 表示全程适用。
    let weeks: [Int]?
    let summary: String
    /// 能否进「这周读什么」。只针对部分人群或有前提条件的条目为 false；
    /// 主题页和本周计数不看它。旧版服务端不带这个字段，缺省为 true。
    let pick: Bool

    init(
        id: String, topic: String, title: String, aliases: [String], weeks: [Int]?,
        summary: String, pick: Bool = true
    ) {
        self.id = id
        self.topic = topic
        self.title = title
        self.aliases = aliases
        self.weeks = weeks
        self.summary = summary
        self.pick = pick
    }

    enum CodingKeys: String, CodingKey {
        case id, topic, title, aliases, weeks, summary, pick
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            topic: try container.decode(String.self, forKey: .topic),
            title: try container.decode(String.self, forKey: .title),
            aliases: try container.decode([String].self, forKey: .aliases),
            weeks: try container.decodeIfPresent([Int].self, forKey: .weeks),
            summary: try container.decode(String.self, forKey: .summary),
            pick: try container.decodeIfPresent(Bool.self, forKey: .pick) ?? true)
    }

    var weeksLabel: String? { encyclopediaWeeksLabel(weeks) }

    func covers(week: Int) -> Bool {
        guard let weeks, weeks.count == 2 else { return true }
        return weeks[0] <= week && week <= weeks[1]
    }

    /// 标了孕周且覆盖本周。全程适用的条目不算「当下」——它们每周都在。
    func isTimely(week: Int?) -> Bool {
        guard let week, weeks != nil else { return false }
        return covers(week: week)
    }
}

struct EncyclopediaCatalog: Decodable, Equatable, Sendable {
    var topics: [EncyclopediaTopic] = []
    var entries: [EncyclopediaEntrySummary] = []

    var isEmpty: Bool { entries.isEmpty }

    /// 「这周读什么」：适用期起点离本周越近越靠前——刚进入适用期的内容最值得现在读。
    /// 标了 `pick == false` 的条目（只针对部分人群）不推荐。
    func picks(forWeek week: Int, limit: Int = 5) -> [EncyclopediaEntrySummary] {
        entries.enumerated()
            .filter { $0.element.pick && $0.element.isTimely(week: week) }
            .sorted { lhs, rhs in
                let l = abs(week - (lhs.element.weeks?.first ?? week))
                let r = abs(week - (rhs.element.weeks?.first ?? week))
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .prefix(limit)
            .map(\.element)
    }

    /// 主题页：本周相关的排前面，其余保持内容文件里的顺序。
    func entries(inTopic topic: String, week: Int?) -> [EncyclopediaEntrySummary] {
        let inTopic = entries.filter { $0.topic == topic }
        return inTopic.filter { $0.isTimely(week: week) } + inTopic.filter { !$0.isTimely(week: week) }
    }

    func timelyCount(topic: String, week: Int?) -> Int {
        entries.filter { $0.topic == topic && $0.isTimely(week: week) }.count
    }
}

struct EncyclopediaEntry: Decodable, Equatable, Sendable, Identifiable {
    struct Section: Decodable, Equatable, Sendable {
        let heading: String
        let text: String
    }

    struct Related: Decodable, Equatable, Sendable, Identifiable {
        let id: String
        let title: String
    }

    let id: String
    let topic: String
    let title: String
    let weeks: [Int]?
    let summary: String
    let sections: [Section]
    let ask: [String]
    let related: [Related]
    let kind: String?
    let link: String?
    let source: String
    let sourceURL: String
    let reviewedAt: String?
    let reviewStatus: String

    var weeksLabel: String? { encyclopediaWeeksLabel(weeks) }
    /// 政策类：App 不下结论，只给官方核对入口。
    var isPolicy: Bool { kind == "policy" }
    var isDraft: Bool { reviewStatus != "reviewed" }

    enum CodingKeys: String, CodingKey {
        case id, topic, title, weeks, summary, sections, ask, related, kind, link, source
        case sourceURL = "source_url"
        case reviewedAt = "reviewed_at"
        case reviewStatus = "review_status"
    }
}
