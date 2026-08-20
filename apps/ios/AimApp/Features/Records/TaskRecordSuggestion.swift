import Foundation

enum TaskRecordSuggestion {
    private static let checkupKeywords = [
        "产检", "检查", "复诊", "B超", "彩超", "超声", "抽血", "验血",
        "糖耐", "唐筛", "NT", "四维", "OGTT", "建档", "胎心监护", "胎监", "尿检", "血压",
    ]

    static func recordType(forTaskTitle title: String) -> RecordType {
        checkupKeywords.contains { title.contains($0) } ? .checkup : .note
    }
}
