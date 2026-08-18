import Foundation

struct AgentChangeRow: Identifiable, Equatable {
    var id: String { field + after }
    let symbol: String
    let field: String
    let before: String?
    let after: String

    var valueText: String {
        guard let before, !before.isEmpty else { return after }
        return "\(before) → \(after)"
    }
}

struct AgentChangePreview: Equatable {
    let understanding: String
    let qualifier: String?
    let changes: [AgentChangeRow]

    static let safetyNote = "Aim 只会修改以上普通计划，不会替你预约或作医疗决定。"

    var applyTitle: String {
        changes.isEmpty ? "确认执行" : "应用 \(changes.count) 项变更"
    }

    static func from(_ request: EveInputRequest) -> AgentChangePreview {
        AgentChangePreview(
            understanding: request.prompt ?? "要执行这项计划变更吗？",
            qualifier: request.qualifier,
            changes: (request.changes ?? []).map {
                AgentChangeRow(symbol: $0.symbol ?? "circle", field: $0.field, before: $0.before, after: $0.after)
            }
        )
    }
}
