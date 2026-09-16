import SafariServices
import SwiftUI

/// 用系统的 Safari 视图打开网页。法律页面这类只读内容用它最省事：
/// 分享、阅读模式、返回都是系统的，不用自己维护一个 WKWebView 外壳。
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Color.aimAccent)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension LegalPage: Identifiable {
    var id: String { rawValue }
}

extension View {
    /// 绑定一个 `LegalPage?`，非 nil 时弹出对应页面。
    func legalPageSheet(_ page: Binding<LegalPage?>, gateway: URL) -> some View {
        sheet(item: page) { selected in
            SafariView(url: AgentWebScheme.legalURL(selected, gateway: gateway))
                .ignoresSafeArea()
        }
    }
}
