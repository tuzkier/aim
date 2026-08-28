import Foundation

/// 对话面页面的地址。
///
/// 页面由后端网关和 `/api/` `/eve/` 一起提供，三者同源。
///
/// 一开始是从 App bundle 经自定义 `aim-app://` scheme 加载的，为的是离线也能起外壳。
/// 那条路走不通：`WKURLSchemeHandler` 会把响应体缓冲到请求结束才交给 `fetch`，
/// 而 Eve 的事件流是长连接、一直不关闭——原生侧数据收齐了，页面上一个字都不出现。
/// 试过主线程回调、重写响应 URL、剥离逐跳头，都不解决；问题在这条路本身。
///
/// 同源加载换来的是事件流天然可用，代价是外壳需要网络。对一个所有数据都在服务端的
/// App 来说，这个代价是可以接受的。
enum AgentWebScheme {
    /// 网关上对话面的路径。与 nginx 的 `location /agent/` 对应。
    static let path = "/agent/"

    static func indexURL(gateway: URL) -> URL {
        URL(string: path, relativeTo: gateway)!.absoluteURL
    }
}
