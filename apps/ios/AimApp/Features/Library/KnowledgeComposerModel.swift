import Foundation

/// 手动新增或编辑一条知识条目。
///
/// 资料库是积累下来的内容，你和 AIM 都能往里加。这个模型服务于
/// 「你自己加」那条路径——AIM 那条走 create_knowledge 工具。
struct KnowledgeComposerModel: Equatable, Sendable {
    var category: LibraryCategoryID
    var form: KnowledgeForm = .tip
    var title: String = ""
    var ingredients: [String] = [""]
    var steps: [String] = [""]
    var verdict: FoodVerdict? = nil
    var reason: String = ""
    var body: String = ""
    var note: String = ""
    var purposes: [String] = [""]

    /// 编辑既有条目：把内容读回表单。
    init(entry: KnowledgeEntry) {
        category = entry.category ?? .nutrition
        form = entry.data.form
        title = entry.title
        ingredients = entry.data.ingredients?.isEmpty == false ? entry.data.ingredients! : [""]
        steps = entry.data.steps?.isEmpty == false ? entry.data.steps! : [""]
        verdict = entry.data.verdict
        reason = entry.data.reason ?? ""
        body = entry.data.body ?? ""
        note = entry.data.note ?? ""
        purposes = entry.data.purposes?.isEmpty == false ? entry.data.purposes! : [""]
    }

    init(category: LibraryCategoryID) {
        self.category = category
        // 吃什么默认按菜谱录，那是这个分类最常加的东西。
        form = category == .nutrition ? .recipe : .tip
    }

    /// 每种形态要求的字段不同，缺了就不让存——后端也会拒，
    /// 不如在按钮上就禁掉，省得保存失败还要猜原因。
    var canSave: Bool { draft() != nil }

    func draft() -> RecordDraft? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let data: KnowledgeRecordData
        switch form {
        case .recipe:
            let ingredients = Self.cleaned(ingredients)
            let steps = Self.cleaned(steps)
            guard !ingredients.isEmpty, !steps.isEmpty else { return nil }
            let purposes = Self.cleaned(purposes)
            data = KnowledgeRecordData(
                category: category.rawValue, form: .recipe,
                ingredients: ingredients, steps: steps, note: Self.optional(note),
                purposes: purposes.isEmpty ? nil : purposes)
        case .foodRule:
            let reason = self.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reason.isEmpty else { return nil }
            data = KnowledgeRecordData(
                category: category.rawValue, form: .foodRule,
                verdict: verdict, reason: reason, note: Self.optional(note))
        case .howto:
            let steps = Self.cleaned(steps)
            guard !steps.isEmpty else { return nil }
            data = KnowledgeRecordData(
                category: category.rawValue, form: .howto,
                steps: steps, note: Self.optional(note))
        case .tip, .unknown:
            let body = self.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            data = KnowledgeRecordData(
                category: category.rawValue, form: .tip,
                body: body, note: Self.optional(note))
        }

        return RecordDraft(
            type: .knowledge, occurredAt: .now, visibility: .family,
            title: trimmedTitle, content: nil, structuredData: .knowledge(data))
    }

    /// 空行是编辑列表时的常态，不该被当成一条内容存进去。
    private static func cleaned(_ values: [String]) -> [String] {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func optional(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
