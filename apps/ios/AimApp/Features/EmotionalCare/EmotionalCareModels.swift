import Foundation

struct MoodRecordData: Codable, Equatable, Sendable {
    let mood: Int
    var tags: [String] = []
    var label: String { Self.labels.indices.contains(mood - 1) ? Self.labels[mood - 1] : "心情记录" }
    static let labels = ["很难受", "有点低落", "还可以", "比较轻松", "很开心"]
    static let tagOptions = [("sleep", "睡眠"), ("worry", "担心"), ("energy", "精力"), ("support", "支持"), ("other", "其他")]
}

enum EmotionalSupportLevel: String, Codable, Sendable {
    case support, followUp = "follow_up", assessment, immediate

    var title: String {
        switch self {
        case .support: "继续留意自己的感受"
        case .followUp: "值得和专业人员聊一聊"
        case .assessment: "建议尽快做进一步评估"
        case .immediate: "先照顾当下的安全"
        }
    }

    var message: String {
        switch self {
        case .support: "这次分数较低，仍不能排除情绪问题。如果持续难受或影响生活，也可以联系专业人员。"
        case .followUp: "建议联系心理或精神卫生专业人员，了解合适的支持。可在 2–4 周后再次自评，不必等到那时才求助。"
        case .assessment: "建议尽快联系医院的心理或精神科，做进一步评估。自评分数不是诊断。"
        case .immediate: "过去 7 天出现过伤害自己的想法，值得现在联系专业人员进一步评估。如果担心马上伤害自己，请让可信赖的人陪着你，去急诊或联系急救，不用等问卷填完或记录保存。"
        }
    }
}

struct EPDSRecordData: Equatable, Sendable {
    let version: String
    let answers: [Int]
    let period: EmotionalPeriod
    var score: Int?
    var item10: Int?
    var supportLevel: EmotionalSupportLevel?
    var levelForDisplay: EmotionalSupportLevel? {
        if (item10 ?? 0) > 0 { return .immediate }
        if version == EPDSQuestionnaire.supportedVersion, answers.count == 10,
           (0..<3).contains(answers[9]) { return .immediate }
        return supportLevel
    }
}

struct EPDSResult: Equatable, Sendable {
    let score: Int
    let item10: Int
    var supportLevel: EmotionalSupportLevel {
        if item10 > 0 { return .immediate }
        if score >= 13 { return .assessment }
        if score >= 10 { return .followUp }
        return .support
    }
}

struct EPDSQuestionnaire: Decodable, Sendable {
    static let supportedVersion = "epds-nsw-zh-Hans-2023-v1"
    struct Question: Decodable, Sendable {
        let id: Int
        let text: String
        let options: [String]
        let points: [Int]
    }
    let version: String
    let title: String
    let instruction: String
    let sourceURL: String
    let questionnaireURL: String
    let attribution: String
    let questions: [Question]

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "epds-zh-Hans", withExtension: "json") else {
            throw QuestionnaireError.unavailable
        }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard value.version == supportedVersion, value.questions.count == 10,
              value.questions.enumerated().allSatisfy({ index, question in
                  question.id == index + 1 && question.options.count == 4 &&
                  question.points == ([0, 1, 3].contains(index) ? [0, 1, 2, 3] : [3, 2, 1, 0])
              }) else { throw QuestionnaireError.unavailable }
        return value
    }

    func result(_ answers: [Int?]) -> EPDSResult? {
        guard answers.count == 10 else { return nil }
        var values: [Int] = []
        for (question, answer) in zip(questions, answers) {
            guard let answer, question.options.indices.contains(answer) else { return nil }
            values.append(question.points[answer])
        }
        return EPDSResult(score: values.reduce(0, +), item10: values[9])
    }

    func hasItem10Concern(_ answers: [Int?]) -> Bool {
        guard answers.count == 10, let choice = answers[9], (0..<4).contains(choice) else { return false }
        return questions[9].points[choice] > 0
    }
}

enum QuestionnaireError: LocalizedError {
    case unavailable
    var errorDescription: String? { "自评资料暂时不可用，请更新 App；现在也可以直接寻求支持。" }
}

enum EmotionalPeriod: String, Codable, Sendable {
    case pregnancyLate = "pregnancy_late", postpartumTwoWeeks = "postpartum_2w"
    case postpartumSixWeeks = "postpartum_6w", manual

    var title: String {
        switch self {
        case .pregnancyLate: "孕晚期自评"
        case .postpartumTwoWeeks: "产后 2 周自评"
        case .postpartumSixWeeks: "产后 6 周自评"
        case .manual: "情绪自评"
        }
    }
}

enum EmotionalSchedule {
    static func isHistoricalAssessment(_ date: Date, now: Date) -> Bool {
        !(0...(7 * 86_400)).contains(now.timeIntervalSince(date))
    }

    static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    static func period(weeks: Int?, birthDate: Date?, now: Date) -> EmotionalPeriod {
        if let birthDate {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: birthDate),
                                               to: calendar.startOfDay(for: now)).day ?? -1
            if (42...365).contains(days) { return .postpartumSixWeeks }
            if (14..<42).contains(days) { return .postpartumTwoWeeks }
            return .manual
        }
        return (28...42).contains(weeks ?? -1) ? .pregnancyLate : .manual
    }

    static func needsAssessment(records: [RecordItem], accountID: UUID, weeks: Int?, dueDate: Date?, birthDate: Date?, now: Date) -> Bool {
        let period = period(weeks: weeks, birthDate: birthDate, now: now)
        guard period != .manual else { return false }
        let start: Date?
        if let birthDate {
            start = calendar.date(byAdding: .day, value: period == .postpartumTwoWeeks ? 14 : 42, to: birthDate)
        } else {
            start = dueDate.flatMap { calendar.date(byAdding: .day, value: -84, to: $0) }
        }
        guard let start else { return true }
        let firstDay = calendar.startOfDay(for: start)
        return !records.contains {
            guard $0.authorAccountID == accountID, $0.occurredAt >= firstDay, $0.occurredAt <= now,
                  case let .epds(data) = $0.structuredData else { return false }
            return data.version == EPDSQuestionnaire.supportedVersion && data.score != nil
        }
    }
}
