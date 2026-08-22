import Foundation

/// 一条待确认写入的知识条目。
///
/// `create_knowledge` 走「执行前确认」档，审批请求里带着完整入参。
/// 有了它，确认卡才能显示「这条菜谱长什么样」，而不是 Eve 默认的
/// 英文提示 "Approve tool call: create_knowledge"。
struct KnowledgePreview: Equatable, Sendable {
    let title: String
    let data: KnowledgeRecordData

    init?(request: EveInputRequest) {
        guard request.toolName == "create_knowledge",
              let input = request.toolInput,
              let title = input["title"]?.stringValue, !title.isEmpty,
              let category = input["category"]?.stringValue,
              let form = input["form"]?.stringValue else { return nil }

        self.title = title
        data = KnowledgeRecordData(
            category: category,
            form: KnowledgeForm(rawValue: form),
            ingredients: input["ingredients"]?.stringArray,
            steps: input["steps"]?.stringArray,
            verdict: input["verdict"]?.stringValue.map(FoodVerdict.init(rawValue:)),
            reason: input["reason"]?.stringValue,
            body: input["body"]?.stringValue,
            note: input["note"]?.stringValue
        )
    }

    var categoryTitle: String {
        LibraryCategoryID(rawValue: data.category)?.title ?? "资料库"
    }

    var formTitle: String {
        switch data.form {
        case .recipe: "菜谱"
        case .foodRule: "能不能吃"
        case .howto: "步骤"
        case .tip, .unknown: "提示"
        }
    }
}
