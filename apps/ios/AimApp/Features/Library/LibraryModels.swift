import Foundation

struct SafetyRule: Identifiable, Equatable, Sendable {
    let id: String
    let condition: String
    let action: String
    let severity: String
    let sourceURL: String

    var isUrgent: Bool { severity == "urgent" }
}

struct APISafetyRuleDTO: Decodable, Sendable {
    let id: String
    let condition: String
    let action: String
    let severity: String
    let sourceURL: String

    enum CodingKeys: String, CodingKey {
        case id, condition, action, severity
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
