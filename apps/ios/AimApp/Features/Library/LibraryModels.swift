import Foundation

struct SafetyRule: Identifiable, Equatable, Sendable {
    let id: String
    let condition: String
    let action: String
    let severity: String
    let sourceURL: String
    /// 只在这段孕周显示，`[起, 止]` 含两端；nil 表示整个孕期都适用。
    var weeks: [Int]? = nil

    /// 立即去急诊或拨打 120。
    var isUrgent: Bool { severity == "urgent" }
    /// 今天或明天联系产检医院。
    var isSameDay: Bool { severity == "same_day" }

    /// 这一条在给定孕周是否适用。
    ///
    /// 孕周取不到、条目没写孕周、或孕周写坏了（个数不对、起点大于终点），一律当作适用——
    /// 危险信号宁可多显示一条，也不能因为缺数据把它藏起来。
    func applies(week: Int?) -> Bool {
        guard let week, let weeks, weeks.count == 2, weeks[0] <= weeks[1] else { return true }
        return weeks[0] <= week && week <= weeks[1]
    }
}

struct APISafetyRuleDTO: Decodable, Sendable {
    let id: String
    let condition: String
    let action: String
    let severity: String
    let sourceURL: String
    /// 老版本接口没有这个字段，解码时缺省为 nil。
    let weeks: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, condition, action, severity, weeks
        case sourceURL = "source_url"
    }
}

struct APISafetyRuleListDTO: Decodable, Sendable {
    let items: [APISafetyRuleDTO]
}

extension SafetyRule {
    init(dto: APISafetyRuleDTO) {
        id = dto.id
        condition = dto.condition
        action = dto.action
        severity = dto.severity
        sourceURL = dto.sourceURL
        weeks = dto.weeks
    }
}


struct ContentItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String
    let verificationURL: String?
    /// 待产包按「证件 / 妈妈 / 宝宝 / 陪产家属」分组——
    /// 一个平铺清单在真收拾的时候没法用。
    let group: String?
}

struct ContentCollection: Equatable, Sendable {
    let id: String
    let source: String
    let sourceURL: String
    let items: [ContentItem]
}

struct APIContentItemDTO: Decodable, Sendable {
    let id: String
    let title: String
    let summary: String
    let verificationURL: String?
    let group: String?

    enum CodingKeys: String, CodingKey {
        case id, title, summary, group
        case verificationURL = "verification_url"
    }
}

struct APIContentCollectionDTO: Decodable, Sendable {
    let id: String
    let source: String
    let sourceURL: String
    let items: [APIContentItemDTO]

    enum CodingKeys: String, CodingKey {
        case id, source, items
        case sourceURL = "source_url"
    }
}

extension ContentCollection {
    init(dto: APIContentCollectionDTO) {
        id = dto.id
        source = dto.source
        sourceURL = dto.sourceURL
        items = dto.items.map {
            ContentItem(id: $0.id, title: $0.title, summary: $0.summary,
                        verificationURL: $0.verificationURL, group: $0.group)
        }
    }
}
