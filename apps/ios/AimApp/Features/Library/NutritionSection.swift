import Foundation

/// 「吃什么」里的两个场景。
///
/// 菜谱回答「做什么」，饮食提示回答「注意什么」——找菜做饭和查能不能吃
/// 是两件事，混在一个列表里两个都不好用。
enum NutritionSection: String, CaseIterable, Identifiable, Sendable {
    case recipes
    case advice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recipes: "菜谱"
        case .advice: "饮食提示"
        }
    }

    var emptyHint: String {
        switch self {
        case .recipes: "记下想再做一次的菜，或让 AIM 帮你收一道"
        case .advice: "能不能吃、该多吃什么、怎么搭配，都记在这里"
        }
    }

    func entries(from entries: [KnowledgeEntry], purpose: String? = nil) -> [KnowledgeEntry] {
        let matching = entries.filter { entry in
            switch self {
            case .recipes: entry.data.form == .recipe
            case .advice: entry.data.form != .recipe
            }
        }
        guard let purpose else { return matching }
        return matching.filter { $0.data.purposes?.contains(purpose) == true }
    }

    /// 可筛的用途来自菜谱自己，不是写死的一张表——用户和 AIM 记什么就有什么。
    ///
    /// 按使用频次排：攒得最多的用途放最前。中文按字符码点排出来的顺序对用户
    /// 没有意义，而「我收了 5 道补铁的菜」本身就说明补铁是当前最关心的。
    static func purposes(in entries: [KnowledgeEntry]) -> [String] {
        var counts: [String: Int] = [:]
        for entry in entries where entry.data.form == .recipe {
            for purpose in entry.data.purposes ?? [] { counts[purpose, default: 0] += 1 }
        }
        return counts.keys.sorted {
            let l = counts[$0] ?? 0, r = counts[$1] ?? 0
            // 频次相同时按名称排，保证结果稳定。
            return l != r ? l > r : $0 < $1
        }
    }
}
