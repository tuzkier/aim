import SwiftUI
import WebKit

/// AIM 的对话面。
///
/// 里面是一个装着 assistant-ui 的 WebView。换掉原来的 ExyteChat 是因为那是个纯消息
/// 控件——`Message(id:user:status:text:)` 里没有位置放执行步骤、思考和内联审批卡。
/// 不是配置不当，是形态不对：用户看不到「执行到哪一步」，一轮里的多个待确认项也
/// 只能显示第一个。
///
/// 呈现方式仍随入口而变：作为 AIM 标签页的根时没有 `onClose`，离开就是切标签；
/// 从「问问 AIM」这类快捷入口打开时是可关闭的浮层——那个入口的全部意义就是
/// 「让我留在原地问一句」。
struct AgentView: View {
    @Environment(AppSessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: AgentStore
    var onClose: (() -> Void)?

    /// 「开新对话」要调用 WebView 里注册的函数，所以得拿得到那个实例。
    @State private var webView: WKWebView?

    var body: some View {
        NavigationStack {
            AgentWebView(
                environment: session.environment,
                colorScheme: colorScheme,
                onNavigate: { _ in
                    // 流里的条目点开后应当落到原生的资料库／记录页。Web 侧目前还没有
                    // 触发跳转的入口，等它有了再把这里接上——先留着通道，
                    // 免得那时又要动一遍 WebView 的配置。
                },
                onTurnFinished: {
                    // 一轮可能改过待办或记录。用通知广播而不是让对话面直接去刷别的 store：
                    // 那样它就得知道全 App 有哪些页面，耦合只会越滚越大。
                    NotificationCenter.default.post(name: .aimAgentTurnFinished, object: nil)
                },
                onCreate: { webView = $0 }
            )
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle("AIM")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", action: onClose)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        webView?.evaluateJavaScript("window.__aimOpenHistory__?.()")
                    } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("历史对话")
                        .accessibilityIdentifier("agent-history")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        webView?.evaluateJavaScript("window.__aimNewConversation__?.()")
                    } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("新对话")
                        .accessibilityIdentifier("agent-new-conversation")
                }
            }
            .background(Color.aimCanvas)
        }
    }
}

extension Notification.Name {
    /// Agent 结束了一轮，可能已经改过待办或记录。
    static let aimAgentTurnFinished = Notification.Name("aim.agentTurnFinished")
}
