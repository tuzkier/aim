import SwiftUI

extension RecordType {
    var displayName: String {
        switch self {
        case .symptom: "身体感受"
        case .checkup: "产检"
        case .note: "随手记"
        case .question: "想问医生"
        case .checklist: "清单"
        case .knowledge: "资料"
        case .fetalMovement: "胎动"
        case .memory: "AIM 记得的事"
        case .contraction: "宫缩"
        case .hospitalTrip: "去医院"
        case .mood: "心情"
        case .epds: "情绪自评"
        case .feeding: "宝宝喂养"
        case .diaper: "宝宝尿布"
        case .sleep: "宝宝睡眠"
        case .unknown: "记录"
        }
    }

    var symbolName: String {
        switch self {
        case .symptom: "heart.text.square"
        case .checkup: "cross.case"
        case .note: "note.text"
        case .question: "questionmark.bubble"
        case .checklist: "checklist"
        case .knowledge: "books.vertical"
        case .fetalMovement: "hand.tap"
        case .memory: "brain"
        case .contraction: "waveform.path.ecg"
        case .hospitalTrip: "car"
        case .mood: "face.smiling"
        case .epds: "heart.text.clipboard"
        case .feeding: "waterbottle"
        case .diaper: "drop"
        case .sleep: "moon.zzz"
        case .unknown: "doc"
        }
    }
}

extension RecordVisibility {
    var displayName: String {
        switch self {
        case .family: "家庭可见"
        case .private: "仅自己可见"
        case .unknown: "未知范围"
        }
    }
}

extension RecordItem {
    @MainActor
    var displayTitle: String {
        switch structuredData {
        case let .memory(data): data.text
        case let .symptom(data): data.symptoms.joined(separator: "、")
        // AIM 建的报告常常没有检查项目，用它的标题（如「10月3日 产检报告」）。
        case let .checkup(data): data.examItems?.trimmed.nilIfEmpty ?? title?.trimmed.nilIfEmpty ?? "产检报告"
        case .note: title?.isEmpty == false ? title! : "随手记"
        case .question: content?.isEmpty == false ? content! : "想问医生"
        case let .checklist(data):
            // 优先用记录自带的标题（勾选时存下来的），否则查内容索引把 id 换回标题。
            // 两条都不成立才用兜底文案——但绝不显示 item_id，那是内部标识。
            title?.trimmed.isEmpty == false
                ? title!.trimmed
                : ContentTitleIndex.title(collection: data.collection, itemID: data.itemID)
                    ?? "清单条目"
        case .knowledge: title ?? "资料"
        case .fetalMovement: "数胎动"
        // 两种都由分娩页生成，标题固定；去医院记录服务端固定写了标题。
        case .contraction: "宫缩计时"
        case .hospitalTrip: title?.trimmed.nilIfEmpty ?? "我们出发去医院了"
        case let .mood(data): "今天的心情 · " + data.label
        case .epds: "情绪自评（EPDS）"
        case .feeding: "宝宝喂养"
        case .diaper: "宝宝尿布"
        case .sleep: "宝宝睡眠"
        case .unknown: type.displayName
        }
    }

    /// 在记录详情里问 AIM 时带的上下文。带上这条记录的编号（小写，与 API
    /// 返回的一致），AIM 才能在回答里用 `[[record:<编号>|…]]` 引用它。
    @MainActor
    var agentContext: AgentContext {
        AgentContext(
            title: "记录",
            summary: "\(type.displayName)：\(displayTitle)\n记录编号：\(id.uuidString.lowercased())"
        )
    }

    var displaySummary: String {
        switch structuredData {
        case let .memory(data): return data.kind.title
        case let .symptom(data):
            let note = data.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "程度 \(data.severity)" + (note.isEmpty ? "" : " · \(note)")
        case let .checkup(data):
            // 四段文字都可选：先看结果，再看医生建议，只有数字的报告就说有指标。
            if let text = data.result?.trimmed.nilIfEmpty ?? data.doctorAdvice?.trimmed.nilIfEmpty { return text }
            return data.metrics.isEmpty && data.otherItems.isEmpty ? "没有补充内容" : "已记下化验指标"
        case .note: return content?.isEmpty == false ? content! : "没有补充内容"
        case let .question(data): return data.answered ? (data.answer ?? "已解答") : "还没问"
        case let .checklist(data): return data.done ? "已完成" : "待完成"
        case let .knowledge(data): return data.body ?? data.reason ?? "资料条目"
        case let .fetalMovement(data): return FetalMovementFormat.summary(data)
        case let .contraction(data): return ContractionFormat.summary(data)
        case let .hospitalTrip(data): return data.reason.displayName
        case let .mood(data): return data.label
        case let .epds(data): return data.score.map { "\($0) / 30 · \(data.levelForDisplay?.title ?? "筛查结果")" } ?? "情绪自评"
        case let .feeding(data): return data.feedingLabel + (data.volumeMl.map { " · \(BabyCareRecordData.amount($0)) 毫升" } ?? " · 奶量未填")
        case let .diaper(data): return data.diaperLabel
        case let .sleep(data): return data.durationSeconds.map { "\($0 / 60) 分钟" } ?? "睡眠记录"
        case .unknown: return "暂不支持展示这类记录"
        }
    }
}
