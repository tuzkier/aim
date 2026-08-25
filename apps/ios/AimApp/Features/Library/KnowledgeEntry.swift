import Foundation

/// 一条知识条目的形态。形态决定它怎么渲染——菜谱要出食材清单和编号步骤，
/// 「能不能吃」要突出结论。
enum KnowledgeForm: String, Codable, Sendable, Equatable {
    case recipe
    case foodRule = "food_rule"
    case howto
    case tip
    case unknown

    init(rawValue: String) {
        switch rawValue {
        case "recipe": self = .recipe
        case "food_rule": self = .foodRule
        case "howto": self = .howto
        case "tip": self = .tip
        default: self = .unknown
        }
    }
}

/// 「能不能吃」的结论。三档而不是能/不能两档——孕期饮食大量情况是
/// 「可以但要限量」，二选一会逼出错误的绝对化结论。
enum FoodVerdict: String, Codable, Sendable, Equatable {
    case safe
    case limit
    case avoid
    case unknown

    init(rawValue: String) {
        switch rawValue {
        case "safe": self = .safe
        case "limit": self = .limit
        case "avoid": self = .avoid
        default: self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .safe: "可以吃"
        case .limit: "可以，但要限量"
        case .avoid: "避免"
        case .unknown: "待确认"
        }
    }
}

struct KnowledgeRecordData: Codable, Equatable, Sendable {
    var category: String
    var form: KnowledgeForm
    var ingredients: [String]?
    var steps: [String]?
    var verdict: FoodVerdict?
    var reason: String?
    var body: String?
    var note: String?
    /// 菜谱的用途标签（补铁、缓解孕吐…）。孕期找菜谱的起点几乎总是
    /// 「我缺铁，吃什么」——用途才是入口，标题不是。
    var purposes: [String]?

    enum CodingKeys: String, CodingKey {
        case category, form, ingredients, steps, verdict, reason, body, note, purposes
    }
}

/// 视图用的知识条目。
struct KnowledgeEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let data: KnowledgeRecordData
    let createdAt: Date

    var category: LibraryCategoryID? { LibraryCategoryID(rawValue: data.category) }

    /// 卡片和列表上的一行摘要。菜谱说有几样食材几步，规则直接说结论——
    /// 让人不点进去也知道这条讲什么。
    var subtitle: String {
        switch data.form {
        case .recipe:
            let ingredients = data.ingredients?.count ?? 0
            let steps = data.steps?.count ?? 0
            let size = "\(ingredients) 样食材 · \(steps) 步"
            guard let purposes = data.purposes, !purposes.isEmpty else { return size }
            return purposes.joined(separator: "、") + " · " + size
        case .foodRule:
            // 结论可选：「补铁要配维C」这类建议没有能吃/不能吃的答案。
            if let verdict = data.verdict { return verdict.displayName }
            return data.reason ?? ""
        case .howto:
            return "\(data.steps?.count ?? 0) 步"
        case .tip, .unknown:
            return data.body ?? ""
        }
    }

    /// 针对这一条提问时的上下文。
    var askContext: AgentContext {
        var lines = ["资料库里的一条记录：\(title)"]
        if let ingredients = data.ingredients { lines.append("食材：" + ingredients.joined(separator: "、")) }
        if let steps = data.steps { lines.append("做法：" + steps.joined(separator: "；")) }
        if let verdict = data.verdict { lines.append("结论：" + verdict.displayName) }
        if let reason = data.reason { lines.append(reason) }
        if let body = data.body { lines.append(body) }
        return AgentContext(title: title, summary: lines.joined(separator: "\n"))
    }

    init?(record: RecordItem) {
        guard record.type == .knowledge,
              case let .knowledge(data) = record.structuredData,
              let title = record.title, !title.isEmpty else { return nil }
        id = record.id
        self.title = title
        self.data = data
        createdAt = record.createdAt
    }
}
