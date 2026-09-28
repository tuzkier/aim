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

/// 这次对话面从哪里打开。与网页端 `bridge.ts` 的 `AgentEntry` 对应。
enum AgentWebEntry: Equatable {
    /// AIM 标签页：接回上一段。
    case resume
    /// 快捷入口：开新的一段，可带页面上下文、可自动发出一句话。
    case new(pageContext: AgentContext?, autoSend: String?)

    var jsonObject: [String: Any] {
        switch self {
        case .resume:
            return ["mode": "resume"]
        case let .new(pageContext, autoSend):
            var object: [String: Any] = ["mode": "new"]
            if let pageContext {
                object["pageContext"] = ["title": pageContext.title, "summary": pageContext.summary]
            }
            if let autoSend { object["autoSend"] = autoSend }
            return object
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
    let entry: AgentWebEntry
    var onNavigate: (AgentWebRoute) -> Void
    /// 参数是这一轮写过的类别（task / record / knowledge），原生据此只刷新受影响的页面。
    var onTurnFinished: ([String]) -> Void
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
                source: Self.contextScript(
                    Self.contextPayload(environment: environment, colorScheme: colorScheme, entry: entry)
                ),
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
        let payload = Self.contextPayload(environment: environment, colorScheme: colorScheme, entry: entry)
        guard payload != context.coordinator.lastPayload else { return }
        context.coordinator.lastPayload = payload
        webView.evaluateJavaScript(
            "window.__AIM_NATIVE__ = \(payload); window.__aimOnContextChanged__?.(\(payload));"
        )
    }

    /// 注入给页面的上下文。用 JSONSerialization 生成——手拼字符串遇到引号就坏了。
    static func contextPayload(
        environment: APIEnvironment,
        colorScheme: ColorScheme,
        entry: AgentWebEntry
    ) -> String {
        var object: [String: Any] = [
            "token": environment.bearerToken ?? "",
            "theme": colorScheme == .dark ? "dark" : "light",
            "entry": entry.jsonObject,
        ]
        // 小写：服务端返回的 UUID 是小写，网页按字符串比对。
        if let familyID = environment.familyID {
            object["familyId"] = familyID.uuidString.lowercased()
        }
        if let pregnancyID = environment.pregnancyID {
            object["pregnancyId"] = pregnancyID.uuidString.lowercased()
        }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func contextScript(_ payload: String) -> String {
        // 在 documentStart 注入：页面的 loadNativeContext 一跑就要能读到，
        // 否则它会走「缺少会话票」的失败分支。
        "window.__AIM_NATIVE__ = \(payload);"
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onNavigate: (AgentWebRoute) -> Void
        var onTurnFinished: ([String]) -> Void
        var lastPayload: String?

        init(onNavigate: @escaping (AgentWebRoute) -> Void, onTurnFinished: @escaping ([String]) -> Void) {
            self.onNavigate = onNavigate
            self.onTurnFinished = onTurnFinished
        }

        func userContentController(
            _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "aimTurnFinished":
                let kinds = (message.body as? [String: Any])?["kinds"] as? [String] ?? []
                onTurnFinished(kinds)
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
