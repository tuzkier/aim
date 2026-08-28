import SwiftUI
import WebKit

/// 原生要处理的、来自对话面的跳转。
enum AgentWebRoute: Equatable {
    case record(UUID)
    case task(UUID)
    case knowledge(UUID)

    init?(body: [String: Any]) {
        guard let kind = body["kind"] as? String,
              let raw = body["id"] as? String,
              let id = UUID(uuidString: raw)
        else { return nil }
        switch kind {
        case "record": self = .record(id)
        case "task": self = .task(id)
        case "knowledge": self = .knowledge(id)
        default: return nil
        }
    }
}

/// AIM 的对话面：一个装着 assistant-ui 的 WKWebView。
///
/// 换掉原来的 ExyteChat 是因为那是个纯消息控件——`Message(id:user:status:text:)` 里
/// 没有位置放执行步骤、思考和内联审批卡。不是配置不当，是形态不对。
///
/// Web 侧不做登录：会话票在这里注入。它已经在原生手上，让 WebView 再登一次意味着
/// 密码要在两处出现，两边的过期时机还会不一致。
struct AgentWebView: UIViewRepresentable {
    let environment: APIEnvironment
    let colorScheme: ColorScheme
    var onNavigate: (AgentWebRoute) -> Void
    var onTurnFinished: () -> Void
    /// 交出实例，好让工具栏上的「新对话」能调到页面里注册的函数。
    var onCreate: (WKWebView) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigate: onNavigate, onTurnFinished: onTurnFinished)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: Self.contextScript(token: environment.bearerToken, colorScheme: colorScheme),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        controller.add(context.coordinator, name: "aimNavigate")
        controller.add(context.coordinator, name: "aimTurnFinished")
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // 页面自己管滚动；再套一层会出现两条滚动条互相抢。
        webView.scrollView.bounces = true
        webView.load(URLRequest(url: AgentWebScheme.indexURL(gateway: environment.baseURL)))
        onCreate(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onNavigate = onNavigate
        context.coordinator.onTurnFinished = onTurnFinished

        // 票据轮换或主题切换后通知页面，而不是重载——重载会把用户正在看的
        // 那一轮连同输入框里的草稿一起丢掉。
        let payload = Self.contextPayload(token: environment.bearerToken, colorScheme: colorScheme)
        guard payload != context.coordinator.lastPayload else { return }
        context.coordinator.lastPayload = payload
        webView.evaluateJavaScript(
            "window.__AIM_NATIVE__ = \(payload); window.__aimOnContextChanged__?.(\(payload));"
        )
    }

    private static func contextPayload(token: String?, colorScheme: ColorScheme) -> String {
        let escapedToken = (token ?? "").replacingOccurrences(of: "\"", with: "\\\"")
        let theme = colorScheme == .dark ? "dark" : "light"
        return "{\"token\":\"\(escapedToken)\",\"theme\":\"\(theme)\"}"
    }

    private static func contextScript(token: String?, colorScheme: ColorScheme) -> String {
        // 在 documentStart 注入：页面的 loadNativeContext 一跑就要能读到，
        // 否则它会走「缺少会话票」的失败分支。
        "window.__AIM_NATIVE__ = \(contextPayload(token: token, colorScheme: colorScheme));"
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onNavigate: (AgentWebRoute) -> Void
        var onTurnFinished: () -> Void
        var lastPayload: String?

        init(onNavigate: @escaping (AgentWebRoute) -> Void, onTurnFinished: @escaping () -> Void) {
            self.onNavigate = onNavigate
            self.onTurnFinished = onTurnFinished
        }

        func userContentController(
            _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "aimTurnFinished":
                onTurnFinished()
            case "aimNavigate":
                // 只认识的路由才转发。页面里传来的东西不该被当成可信输入，
                // 认不出来就丢掉，而不是猜。
                guard let body = message.body as? [String: Any],
                      let route = AgentWebRoute(body: body)
                else { return }
                onNavigate(route)
            default:
                break
            }
        }
    }
}
