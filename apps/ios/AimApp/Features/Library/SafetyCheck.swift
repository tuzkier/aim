import Foundation

/// 危险信号的症状自查。
///
/// 危险信号此前是一段只读文字。但真出血的时候没人有心情通读——
/// 应该是勾出正在经历的情况，直接给结论。
///
/// 判断规则刻意简单：勾中任何一条紧急项就是立即就医，不做加权也不做打折。
/// 这里不是在做分诊，只是把内容库里已经写明的处理建议对应出来。
enum SafetyCheck {
    enum Level: Equatable, Sendable {
        /// 立即就医。
        case now
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
            return Verdict(
                level: .now,
                headline: "请立即联系产检医院或急救服务",
                actions: actions)
        }
        return Verdict(
            level: .mention,
            headline: "记下来，下次产检时告诉医生",
            actions: actions)
    }
}
