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
    @Environment(AgentDestinations.self) private var destinations: AgentDestinations?
    @Bindable var store: AgentStore
    var onClose: (() -> Void)?

    /// 头部那几颗钮要调页面里注册的函数，所以得拿得到 WebView 实例。
    @State private var webView: WKWebView?
    @State private var entry: AgentWebEntry
    @State private var destination: AgentDestination?

    init(store: AgentStore, onClose: (() -> Void)? = nil) {
        self.store = store
        self.onClose = onClose
        // 在创建时定下入口并存进 @State：视图重建时 init 会再跑，但入口不能跟着变，
        // 否则 WebView 会拿到一个新的 entry 把对话切走。
        _entry = State(initialValue: onClose == nil
            ? .resume
            : .new(pageContext: store.context, autoSend: store.pendingAutoSend, attachImage: store.pendingImage))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                AgentWebView(
                    environment: session.environment,
                    colorScheme: colorScheme,
                    entry: entry,
                    onNavigate: { route in
                        // 卡片上的「查看」落到原生详情页，而不是在 WebView 里再画一遍。
                        Task { destination = await destinations?.resolve(route) }
                    },
                    onTurnFinished: { kinds in
                        // 一轮可能改过待办或记录。用通知广播而不是让对话面直接去刷别的
                        // store：那样它就得知道全 App 有哪些页面，耦合只会越滚越大。
                        NotificationCenter.default.post(
                            name: .aimDataChanged, object: nil, userInfo: ["kinds": kinds]
                        )
                    },
                    onCreate: { webView = $0 }
                )
            }
            .background(Color.aimCanvas)
            .navigationTitle("AIM")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $destination) { target in
                destinationView(target)
            }
        }
        .onAppear {
            store.pendingAutoSend = nil
            store.pendingImage = nil
            // 标签页重新出现：若刚才在快捷入口里开了新的一段，切过去。
            if onClose == nil {
                webView?.evaluateJavaScript("window.__aimOnAppear__?.()")
            }
        }
    }

    private func destinationView(_ target: AgentDestination) -> some View {
        AgentDestinationView(target: target)
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
                Text("AIM 的建议不能替代医生诊断，紧急情况请立即就医")
                    .font(.caption2)
                    .foregroundStyle(Color.aimTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("agent-disclaimer")
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

/// 按目标显示原生详情页。AIM 对话卡片、家庭动态、成员详情共用。
struct AgentDestinationView: View {
    @Environment(AgentDestinations.self) private var destinations: AgentDestinations?
    let target: AgentDestination

    var body: some View {
        switch target {
        case let .task(task):
            TaskDetailView(task: task, repository: destinations?.planStore.repository)
        case let .record(record):
            if let destinations {
                RecordDetailView(
                    record: record,
                    store: destinations.recordStore,
                    planStore: destinations.planStore,
                    agentStore: destinations.agentStore
                )
            }
        case let .knowledge(entry):
            KnowledgeDetailView(entry: entry, agentStore: nil)
        }
    }
}

/// 对话卡片上「查看」要去的原生页面。按 id 判等，好放进 navigationDestination。
enum AgentDestination: Identifiable, Hashable {
    case task(TaskItem)
    case record(RecordItem)
    case knowledge(KnowledgeEntry)

    var id: String {
        switch self {
        case let .task(task): "task-\(task.id)"
        case let .record(record): "record-\(record.id)"
        case let .knowledge(entry): "knowledge-\(entry.id)"
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 把网页传来的 id 换成原生页面要的模型。
///
/// 放在环境里而不是给每个 `AgentView` 调用点加参数：快捷入口有七处，
/// 它们都只是「打开对话面」，不该各自认识三个 store。
@MainActor
@Observable
final class AgentDestinations {
    let planStore: PlanStore
    let recordStore: RecordStore
    let libraryStore: LibraryStore
    let agentStore: AgentStore

    init(planStore: PlanStore, recordStore: RecordStore, libraryStore: LibraryStore, agentStore: AgentStore) {
        self.planStore = planStore
        self.recordStore = recordStore
        self.libraryStore = libraryStore
        self.agentStore = agentStore
    }

    /// 先查已加载的数据；查不到就刷新一次再查——AIM 可能刚刚才建了它。
    func resolve(_ route: AgentWebRoute) async -> AgentDestination? {
        if let hit = lookup(route) { return hit }
        switch route {
        case .task: await planStore.load()
        case .record: await recordStore.load()
        case .knowledge: await libraryStore.load()
        }
        return lookup(route)
    }

    private func lookup(_ route: AgentWebRoute) -> AgentDestination? {
        switch route {
        case let .task(id):
            planStore.snapshot?.tasks.first { $0.id == id }.map(AgentDestination.task)
        case let .record(id):
            recordStore.snapshot?.records.first { $0.id == id }.map(AgentDestination.record)
        case let .knowledge(id):
            libraryStore.snapshot.records.first { $0.id == id }
                .flatMap(KnowledgeEntry.init(record:))
                .map(AgentDestination.knowledge)
        }
    }
}

/// 把一阵「AIM 写过东西」的通知合并成尽量少的刷新。
///
/// 刷新一轮要打好几个接口；上一轮还没跑完时又来的通知不另起一轮，而是记下类别，
/// 等这一轮结束后按并集再跑一次。批量操作时不会把接口打到被网关限流。
@MainActor
final class AgentRefreshCoalescer {
    private var pending = Set<String>()
    private var running = false
    private let perform: (Set<String>) async -> Void

    init(perform: @escaping (Set<String>) async -> Void) {
        self.perform = perform
    }

    func request(_ kinds: Set<String>) async {
        pending.formUnion(kinds)
        guard !running else { return }
        running = true
        while !pending.isEmpty {
            let batch = pending
            pending = []
            await perform(batch)
        }
        running = false
    }
}

extension Notification.Name {
    /// 待办、记录或资料被改过（AIM 写入，或原生页面删除等）。
    /// userInfo["kinds"] 是受影响的类别：task / record / knowledge。
    static let aimDataChanged = Notification.Name("aim.dataChanged")
}
