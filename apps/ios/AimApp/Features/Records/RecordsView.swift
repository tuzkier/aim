import SwiftUI

extension RecordType {
    var displayName: String {
        switch self {
        case .symptom: "身体感受"
        case .checkup: "产检"
        case .note: "随手记"
        case .unknown: "记录"
        }
    }

    var symbolName: String {
        switch self {
        case .symptom: "heart.text.square"
        case .checkup: "cross.case"
        case .note: "note.text"
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
    var displayTitle: String {
        switch structuredData {
        case let .symptom(data): data.symptoms.joined(separator: "、")
        case let .checkup(data): data.examItems
        case .note: title?.isEmpty == false ? title! : "随手记"
        case .unknown: type.displayName
        }
    }

    var displaySummary: String {
        switch structuredData {
        case let .symptom(data):
            let note = data.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "程度 \(data.severity)" + (note.isEmpty ? "" : " · \(note)")
        case let .checkup(data): return data.result
        case .note: return content?.isEmpty == false ? content! : "没有补充内容"
        case .unknown: return "暂不支持展示这类记录"
        }
    }
}
