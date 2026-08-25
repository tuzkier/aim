import Foundation

/// 一份带去产检的问诊清单。
///
/// 「想问医生」此前只能一条条加、一条条划掉，缺了最关键的一步：
/// 产检那天怎么把攒下的问题一次性带走。
struct ConsultationList: Equatable, Sendable {
    struct Question: Identifiable, Equatable, Sendable {
        let id: UUID
        let text: String
    }

    let questions: [Question]

    var recordIDs: [UUID] { questions.map(\.id) }

    /// 可复制的纯文本。带编号，便于直接给医生看或发给家人。
    var plainText: String {
        questions.enumerated()
            .map { "\($0.offset + 1). \($0.element.text)" }
            .joined(separator: "\n")
    }

    static func make(from snapshot: LibrarySnapshot) -> ConsultationList? {
        let pending = snapshot.records
            .filter { record in
                guard record.type == .question,
                      case let .question(data) = record.structuredData else { return false }
                // 问过的带去只会浪费医生时间。
                return !data.answered
            }
            // 按攒下来的先后排，先想到的先问。
            .sorted { $0.occurredAt < $1.occurredAt }
            .compactMap { record -> Question? in
                guard let text = record.content, !text.isEmpty else { return nil }
                return Question(id: record.id, text: text)
            }
        return pending.isEmpty ? nil : ConsultationList(questions: pending)
    }
}
