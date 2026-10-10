import Foundation

/// 资料库的一份数据快照。分类的摘要都从它算出来，视图不直接碰仓储。
struct LibrarySnapshot: Equatable, Sendable {
    var records: [RecordItem] = []
    var safetyRuleCount: Int = 0
    /// 内容集合的条目总数。清单类分类的进度是「已勾选记录数 / 集合条目数」，
    /// 两边缺一不可——内容还没加载出来时不能显示 0/0，那看起来像没有内容。
    var collectionSizes: [String: Int] = [:]
    /// 百科各主题的条目数。「吃什么」没有用户条目时优先用饮食主题的数量做摘要，
    /// 为空（生产尚未发布百科）时回退到 nutrition 集合的条目数。
    var encyclopediaCounts: [String: Int] = [:]
}

/// 一张分类卡上显示的活数据。
///
/// 卡片刻意不是纯标题——`headline` 回答「这里现在有多少东西」，
/// `tags` 给出最值得被看见的几条。空数据时 `headline` 也要有话说，
/// 不能留一张空卡。
struct LibrarySummary: Equatable, Sendable {
    let headline: String
    var tags: [String] = []
    var detail: String?
}

enum LibraryCategoryID: String, CaseIterable, Identifiable, Sendable {
    case checkups
    case nutrition
    case symptoms
    case questions
    case paperwork
    case preparation
    case safety
    case fetalMovement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .checkups: "产检与指标"
        case .nutrition: "吃什么"
        case .symptoms: "身体感受"
        case .questions: "想问医生"
        case .paperwork: "办事指南"
        case .preparation: "待产准备"
        case .safety: "危险信号"
        case .fetalMovement: "胎动"
        }
    }

    var icon: String {
        switch self {
        case .checkups: "stethoscope"
        case .nutrition: "fork.knife"
        case .symptoms: "heart.text.square"
        case .questions: "questionmark.bubble"
        case .paperwork: "doc.text"
        case .preparation: "suitcase"
        case .safety: "exclamationmark.triangle"
        case .fetalMovement: "hand.tap"
        }
    }

    /// 该分类下用户积累的知识条目。
    func entries(in snapshot: LibrarySnapshot) -> [KnowledgeEntry] {
        snapshot.records
            .compactMap(KnowledgeEntry.init(record:))
            .filter { $0.category == self }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func summary(from snapshot: LibrarySnapshot) -> LibrarySummary {
        // 用户自己积累的条目优先于静态基线——那才是这个分类的价值所在。
        let entries = entries(in: snapshot)
        if !entries.isEmpty {
            return LibrarySummary(
                headline: "\(entries.count) 条资料",
                tags: entries.prefix(2).map(\.title),
                detail: entries.first?.subtitle
            )
        }
        switch self {
        case .symptoms:
            return Self.symptomSummary(from: snapshot)
        case .checkups:
            let count = snapshot.records.filter { $0.type == .checkup }.count
            return count == 0
                ? LibrarySummary(headline: "还没有产检记录")
                : LibrarySummary(headline: "\(count) 次记录")
        case .safety:
            return snapshot.safetyRuleCount == 0
                ? LibrarySummary(headline: "出现这些情况立即就医")
                : LibrarySummary(headline: "\(snapshot.safetyRuleCount) 条")
        case .questions:
            return Self.questionSummary(from: snapshot)
        case .fetalMovement:
            let latest = snapshot.records
                .compactMap(FetalMovementSession.init(record:))
                .max { $0.startedAt < $1.startedAt }
            guard let latest else { return LibrarySummary(headline: "28 周起每天数一数") }
            return LibrarySummary(headline: FetalMovementFormat.summary(latest.data))
        case .paperwork:
            return Self.checklistSummary(
                from: snapshot, collection: "hangzhou", format: { "\($0)/\($1) 已办妥" })
        case .preparation:
            return Self.checklistSummary(
                from: snapshot, collection: "preparation", format: { "待产包 \($0)/\($1)" })
        case .nutrition:
            let diet = snapshot.encyclopediaCounts["diet"] ?? 0
            let total = diet > 0 ? diet : snapshot.collectionSizes["nutrition"] ?? 0
            guard total > 0 else {
                return LibrarySummary(headline: Self.placeholderHeadline(for: self))
            }
            return LibrarySummary(headline: "\(total) 条饮食提示")
        }
    }

    /// 在某个分类里问 AIM 时带的上下文。要说清「这是哪个分类」，
    /// 否则模型不知道该往哪里存。
    @MainActor
    func askContext(from snapshot: LibrarySnapshot) -> AgentContext {
        var lines = ["当前在资料库的「\(title)」分类"]
        let entries = entries(in: snapshot)
        if !entries.isEmpty {
            lines.append("已收录：" + entries.prefix(5).map(\.title).joined(separator: "、"))
        }
        if let ids = recordIDLine(from: snapshot) { lines.append(ids) }
        lines.append("如果我要你记录什么，请存进这个分类。")
        return AgentContext(title: title, summary: lines.joined(separator: "\n"))
    }

    /// 进入分类后调起 AIM 时带的上下文，与时间线头部同一套机制。
    @MainActor
    func agentContext(from snapshot: LibrarySnapshot) -> AgentContext {
        let summary = summary(from: snapshot)
        var lines = [summary.headline]
        if !summary.tags.isEmpty { lines.append(summary.tags.joined(separator: "、")) }
        if let ids = recordIDLine(from: snapshot) { lines.append(ids) }
        return AgentContext(title: title, summary: lines.joined(separator: "\n"))
    }

    /// 产检与身体感受带上最近 5 条记录的编号（按时间倒序），AIM 才能在回答里
    /// 用 `[[record:<编号>|…]]` 引用具体那一次。其他分类、没有记录时不加这一行。
    /// 编号用小写，与 API 返回、AIM 工具里出现的写法一致。
    @MainActor
    private func recordIDLine(from snapshot: LibrarySnapshot) -> String? {
        let type: RecordType
        switch self {
        case .checkups: type = .checkup
        case .symptoms: type = .symptom
        default: return nil
        }
        let recent = snapshot.records
            .filter { $0.type == type }
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(5)
        guard !recent.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        let items = recent.map { "\($0.id.uuidString.lowercased())（\(formatter.string(from: $0.occurredAt)) \($0.displayTitle)）" }
        return "记录编号：" + items.joined(separator: "；")
    }

    private static func placeholderHeadline(for id: LibraryCategoryID) -> String {
        switch id {
        case .nutrition: "食谱与禁忌，即将上线"
        case .questions: "攒下想问医生的问题"
        case .paperwork: "建卡、生育险、证件"
        case .preparation: "待产包与婴儿用品"
        default: "暂无内容"
        }
    }

    private static func questionSummary(from snapshot: LibrarySnapshot) -> LibrarySummary {
        let questions = snapshot.records.compactMap { record -> (RecordItem, QuestionRecordData)? in
            guard record.type == .question,
                  case let .question(data) = record.structuredData else { return nil }
            return (record, data)
        }
        guard !questions.isEmpty else {
            return LibrarySummary(headline: placeholderHeadline(for: .questions))
        }
        // 只数还没问的——问过的不该继续占用注意力。
        let pending = questions.filter { !$0.1.answered }
        guard !pending.isEmpty else { return LibrarySummary(headline: "都问过了") }
        let latest = pending.max { $0.0.occurredAt < $1.0.occurredAt }
        return LibrarySummary(
            headline: "攒了 \(pending.count) 个问题",
            detail: latest?.0.content
        )
    }

    private static func checklistSummary(
        from snapshot: LibrarySnapshot,
        collection: String,
        format: (Int, Int) -> String
    ) -> LibrarySummary {
        guard let total = snapshot.collectionSizes[collection], total > 0 else {
            return LibrarySummary(headline: placeholderHeadline(for: collection == "preparation" ? .preparation : .paperwork))
        }
        let done = snapshot.records.filter { record in
            guard case let .checklist(data) = record.structuredData else { return false }
            return data.collection == collection && data.done
        }.count
        return LibrarySummary(headline: format(done, total))
    }

    private static func symptomSummary(from snapshot: LibrarySnapshot) -> LibrarySummary {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let recent = snapshot.records.filter { $0.type == .symptom && $0.occurredAt >= cutoff }
        guard !recent.isEmpty else { return LibrarySummary(headline: "还没有记录身体感受") }

        var counts: [String: Int] = [:]
        var order: [String] = []
        for record in recent {
            guard case let .symptom(data) = record.structuredData else { continue }
            for label in data.symptoms {
                if counts[label] == nil { order.append(label) }
                counts[label, default: 0] += 1
            }
        }
        // 出现次数多的排前面；同次数按首次出现顺序，保证结果稳定。
        let tags = order
            .sorted { lhs, rhs in
                let l = counts[lhs] ?? 0, r = counts[rhs] ?? 0
                if l != r { return l > r }
                return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
            }
            .prefix(3)
            .map { label in
                let count = counts[label] ?? 0
                return count > 1 ? "\(label) ×\(count)" : label
            }
        return LibrarySummary(headline: "近 7 天 \(recent.count) 条", tags: Array(tags))
    }
}

struct LibraryCategory: Identifiable, Sendable {
    let id: LibraryCategoryID
    /// 危险信号单独通栏，不参与网格——它是安全兜底，不该和食谱平级。
    let isBanner: Bool

    var title: String { id.title }
    var icon: String { id.icon }
}

/// 分类目录是数据不是代码：新增一个分类是往这里加一条，而不是改视图。
enum LibraryCatalog {
    static let categories: [LibraryCategory] = [
        LibraryCategory(id: .checkups, isBanner: false),
        LibraryCategory(id: .nutrition, isBanner: false),
        LibraryCategory(id: .symptoms, isBanner: false),
        LibraryCategory(id: .questions, isBanner: false),
        LibraryCategory(id: .fetalMovement, isBanner: false),
        LibraryCategory(id: .paperwork, isBanner: false),
        LibraryCategory(id: .preparation, isBanner: false),
        LibraryCategory(id: .safety, isBanner: true),
    ]

    static var gridCategories: [LibraryCategory] { categories.filter { !$0.isBanner } }
    static var bannerCategories: [LibraryCategory] { categories.filter(\.isBanner) }
}
