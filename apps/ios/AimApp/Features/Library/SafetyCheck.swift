import Foundation

/// 危险信号的症状自查。
///
/// 危险信号此前是一段只读文字。但真出血的时候没人有心情通读——
/// 应该是勾出正在经历的情况，直接给结论。
///
/// 判断规则刻意简单：按勾中条目里最严重的一档给结论，不做加权也不做打折。
/// 这里不是在做分诊，只是把内容库里已经写明的处理建议对应出来。
enum SafetyCheck {
    enum Level: Equatable, Sendable {
        /// 立即就医。
        case now
        /// 今天或明天联系产检医院。
        case soon
        /// 下次产检时告诉医生。
        case mention
    }

    struct Verdict: Equatable, Sendable {
        let level: Level
        let headline: String
        /// 勾中条目各自的处理建议，而不是笼统一句话。
        let actions: [String]
    }

    static func verdict(for selected: Set<String>, in rules: [SafetyRule]) -> Verdict? {
        // 不认识的 id 直接忽略，不能因为一条脏数据给出错误结论。
        let matched = rules.filter { selected.contains($0.id) }
        guard !matched.isEmpty else { return nil }

        let actions = matched.map(\.action)
        if matched.contains(where: \.isUrgent) {
            return Verdict(level: .now, headline: "请立即联系产检医院或拨打 120", actions: actions)
        }
        if matched.contains(where: \.isSameDay) {
            return Verdict(level: .soon, headline: "今天或明天联系你的产检医院", actions: actions)
        }
        return Verdict(level: .mention, headline: "记下来，下次产检时告诉医生", actions: actions)
    }

    /// 结论只看当前孕周能看到的条目：被孕周藏起来的勾选不能再左右结论。
    static func verdict(for selected: Set<String>, in rules: [SafetyRule], forWeek week: Int?) -> Verdict? {
        verdict(for: selected, in: self.rules(rules, forWeek: week))
    }

    /// 孕周或条目变了之后还留得住的勾选：看不见的、不认识的都清掉。
    static func visibleSelection(_ selected: Set<String>, in rules: [SafetyRule], forWeek week: Int?) -> Set<String> {
        selected.intersection(self.rules(rules, forWeek: week).map(\.id))
    }

    /// 自查页要显示的条目：只留当前孕周适用的，紧急 → 当天联系 → 下次产检，同档保持原序。
    ///
    /// 孕周取不到时返回全部。20 周以后的出血会同时命中两条紧急项，两条都留着——
    /// 用户勾哪条结论都一样，去重反而可能让人找不到自己那条说法。
    static func rules(_ rules: [SafetyRule], forWeek week: Int?) -> [SafetyRule] {
        rules.enumerated()
            .filter { $0.element.applies(week: week) }
            .sorted { lhs, rhs in
                let (l, r) = (rank(lhs.element), rank(rhs.element))
                // 标准库的排序不保证稳定，同档用原下标兜住顺序。
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func rank(_ rule: SafetyRule) -> Int {
        if rule.isUrgent { return 0 }
        if rule.isSameDay { return 1 }
        return 2
    }
}
