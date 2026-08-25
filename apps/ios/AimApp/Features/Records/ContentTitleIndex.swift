import Foundation

/// 内容条目 id → 人能读的标题。
///
/// checklist 记录只存 `collection` + `item_id`（这是对的：标题以后随内容更新，
/// 老记录跟着显示新标题，不会留下过时文案）。但显示时必须把 id 换回标题，
/// 否则界面上出现的就是 `maternity-benefits-materials` 这种内部标识。
///
/// 做成共享索引而不是给 `displayTitle` 加参数：它被时间线、记录详情、
/// Agent 提示词等六处调用，逐个把内容集合传进去会把这份静态参考数据
/// 拖成到处流动的依赖。内容是全局只读的，索引也就该是全局只读的。
@MainActor
enum ContentTitleIndex {
    private static var titles: [String: String] = [:]

    private static func key(collection: String, itemID: String) -> String {
        "\(collection)/\(itemID)"
    }

    static func register(_ collections: [String: ContentCollection]) {
        for (name, collection) in collections {
            for item in collection.items {
                titles[key(collection: name, itemID: item.id)] = item.title
            }
        }
    }

    static func title(collection: String, itemID: String) -> String? {
        titles[key(collection: collection, itemID: itemID)]
    }

    /// 仅供测试重置，避免用例之间互相干扰。
    static func reset() {
        titles = [:]
    }
}
