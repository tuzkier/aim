import Foundation

/// 分娩模式的医学文案。集中在这里便于产科医生复核（见 content/README.md「待产科医生复核」）。
/// 原则：不说「正常」，不说「还不用去」；5-1-1 只是参考，以医生交代为准。
enum LaborCopy {
    static let pretermBanner = "还没满 37 周。出现规律宫缩可能是早产，不用等到 5-1-1，请现在联系医院。"

    static let goNowTitle = "这些情况不用等宫缩规律，立即去医院"
    static let goNowItems = [
        "破水（不管有没有宫缩）",
        "阴道流血像月经那么多或更多",
        "持续剧烈腹痛，不缓解",
        "胎动明显减少或停止",
        "头痛、眼花、抽搐",
        "不足 37 周出现规律宫缩",
    ]

    static let whenToLeaveTitle = "什么时候出发"
    static let whenToLeave = [
        "第一次生的常用参考「5-1-1」：约 5 分钟一次、每次约 1 分钟、持续 1 小时。",
        "生过孩子的产程可能更快，宫缩规律（约 10 分钟一次）就联系医院。",
        "医生交代过别的时机，以医生为准。",
    ]
    static let doctorFirst = "医生交代过别的时机，以医生为准"

    static func stageTitle(_ stage: ContractionStage) -> String {
        switch stage {
        case .early: "还不规律，继续记录"
        case .approaching: "越来越规律了"
        case .go: "符合 5-1-1，现在出发去医院"
        case .pretermAlert: "未满 37 周宫缩频繁，现在联系医院"
        }
    }

    static func stageDetail(_ stage: ContractionStage) -> String {
        switch stage {
        case .early: "可以休息、吃点东西、喝水，继续按开始和结束。出现下面的情况不用等，立即去医院。"
        case .approaching: "收好待产包、安排好车、告诉家人。生过孩子的，现在就联系医院。"
        case .go: "按医生交代的去医院。路上继续计时也可以。"
        case .pretermAlert: "可能是早产。请现在联系你的产检医院或去产科急诊，必要时拨打 120。"
        }
    }

    static func quiet(minutes: Int) -> String { "已经 \(minutes) 分钟没有宫缩了" }
    static let longRunning = "这次宫缩已经超过 3 分钟。如果是持续剧痛不缓解，请立即去医院。忘了按结束就现在按。"

    static let tripExplanation = "家人下次打开 App 会在首页看到。现在还不能推送到他们的手机，急事请直接打电话。"
    static let tripSaved = "已告诉家人。路上注意安全"
    static let staleTitle = "上次计时还没保存"
    static let staleMessage = "最后一次宫缩已经过去 6 个多小时。先保存或丢弃，再开始新的计时。"
}
