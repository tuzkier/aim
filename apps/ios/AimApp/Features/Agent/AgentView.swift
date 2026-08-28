import SwiftUI
import WebKit

/// AIM 的对话面。
///
/// 里面是一个装着 assistant-ui 的 WebView。换掉原来的 ExyteChat 是因为那是个纯消息
/// 控件——`Message(id:user:status:text:)` 里没有位置放执行步骤、思考和内联审批卡。
/// 不是配置不当，是形态不对：用户看不到「执行到哪一步」，一轮里的多个待确认项也
/// 只能显示第一个。
///
/// 头部刻意和资料库、孕期那些标签页同构：内容区大标题 + 右上角 32pt 小圆钮，
/// 导航栏隐藏。此前用的是居中的系统导航栏加两颗大圆钮，在标签之间来回切的时候
/// 像是走进了另一个 App。
///
/// 呈现方式仍随入口而变：作为 AIM 标签页的根时没有 `onClose`，离开就是切标签；
/// 从「问问 AIM」这类快捷入口打开时多一颗关闭钮——那个入口的全部意义就是
/// 「让我留在原地问一句」。
struct AgentView: View {
    @Environment(AppSessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: AgentStore
    var onClose: (() -> Void)?

    /// 头部那几颗钮要调页面里注册的函数，所以得拿得到 WebView 实例。
    @State private var webView: WKWebView?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                AgentWebView(
                    environment: session.environment,
                    colorScheme: colorScheme,
                    onNavigate: { _ in
                        // 流里的条目点开后应当落到原生的资料库／记录页。Web 侧目前还没有
                        // 触发跳转的入口，等它有了再把这里接上——先留着通道，
                        // 免得那时又要动一遍 WebView 的配置。
                    },
                    onTurnFinished: {
                        // 一轮可能改过待办或记录。用通知广播而不是让对话面直接去刷别的
                        // store：那样它就得知道全 App 有哪些页面，耦合只会越滚越大。
                        NotificationCenter.default.post(name: .aimAgentTurnFinished, object: nil)
                    },
                    onCreate: { webView = $0 }
                )
            }
            .background(Color.aimCanvas)
            .navigationTitle("AIM")
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// 与 `LibraryView.header` 同一形态。
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: AimMetrics.space4) {
                Text("AIM")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color.aimTextPrimary)
                Text("孕期里的事，说一声就好")
                    .font(.caption)
                    .foregroundStyle(Color.aimTextTertiary)
            }
            Spacer()
            circleButton("clock.arrow.circlepath", label: "历史对话", id: "agent-history") {
                webView?.evaluateJavaScript("window.__aimOpenHistory__?.()")
            }
            circleButton("square.and.pencil", label: "新对话", id: "agent-new-conversation") {
                webView?.evaluateJavaScript("window.__aimNewConversation__?.()")
            }
            if let onClose {
                circleButton("xmark", label: "关闭", id: "agent-close", action: onClose)
            }
        }
        .padding(.horizontal, AimMetrics.space16)
        .padding(.top, AimMetrics.space16)
        .padding(.bottom, AimMetrics.space12)
    }

    private func circleButton(
        _ symbol: String,
        label: String,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: AimMetrics.circleButtonSize, height: AimMetrics.circleButtonSize)
                .background(Color.aimAccentSoft, in: Circle())
                .foregroundStyle(Color.aimAccent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

extension Notification.Name {
    /// Agent 结束了一轮，可能已经改过待办或记录。
    static let aimAgentTurnFinished = Notification.Name("aim.agentTurnFinished")
}
