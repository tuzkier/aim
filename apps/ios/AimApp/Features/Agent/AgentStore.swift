import Foundation
import Observation

@MainActor
@Observable
final class AgentStore {
    var state: AgentSheetState = .idle
    var messages: [AgentMessage] = []
    var draft = ""
    var sessionID: String?
    var streamIndex = 0
    var continuationToken: String?

    var context: AgentContext?
    var activityLog: [AgentActivity] = []

    /// 当前批次里全部待处理的审批。
    ///
    /// Eve 把同一轮里的多个工具审批打成**一个批次**下发（`input.requested` 的
    /// `requests` 是数组），并且整批凑齐才结算。此前这里只留 `.first`，另外几条
    /// 再也没有入口，于是整轮一直 parked：模型输出被扣住不发，批内工具一个都不
    /// 执行——线上「让 AIM 收几道菜，卡片闪一下就没了，一道也没存」就是这么来的。
    private(set) var pendingApprovals: [EveInputRequest] = []

    /// 批次内逐条累积的决定，requestID -> 同意与否。
    private(set) var approvalDecisions: [String: Bool] = [:]

    /// 批次里还没拿到回音的那些。
    var unansweredApprovals: [EveInputRequest] {
        pendingApprovals.filter { approvalDecisions[$0.requestID] == nil }
    }

    /// 整批都有回音了，这时才能把响应发回 Eve。
    var isApprovalBatchComplete: Bool {
        !pendingApprovals.isEmpty && unansweredApprovals.isEmpty
    }

    /// 记下其中一条的决定。否决一条不代表放弃整批——剩下的仍要答完，
    /// 否则批次不结算，已经同意的那几条也跟着卡住。
    func recordApproval(requestID: String, approved: Bool) {
        guard pendingApprovals.contains(where: { $0.requestID == requestID }) else { return }
        approvalDecisions[requestID] = approved
    }

    private func beginApprovalBatch(_ requests: [EveInputRequest]) {
        pendingApprovals = requests
        approvalDecisions = [:]
    }

    /// 撤销「新建」类操作直接调删除接口，不经过模型。
    var repository: BusinessRepositoryProtocol?
    /// 会话目录。新对话开始时要登记，回到旧对话时要顶到最前。
    var sessions: AgentSessionStore?

    private var client: EveClient?
    private var activeTask: Task<Void, Never>?
    private var lastUserText: String?
    /// 重放历史对话时为真。实时发送时用户消息是本地 append 的，
    /// 只有重放才需要从 message.received 事件里还原它，否则会重复两条。
    private var isReplaying = false

    init(context: AgentContext? = nil) {
        self.context = context
    }

    func requestMessage(for text: String) -> String {
        guard let context else { return text }
        return "\(context.prompt)\n\n用户问题：\(text)"
    }

    /// Bring the current page's context into view without sending anything —
    /// used when the entry point is "quickly ask about what I'm looking at",
    /// not a specific question. Doesn't clear existing conversation history:
    /// this store is shared across every entry point, so switching context
    /// mid-conversation is expected, not a reset.
    func focus(context: AgentContext?) {
        // 快捷入口开新的一段：一段对话里混十几件不相干的事，以后没法翻。
        // 当前这段不会丢——它已经在会话目录里。
        startNewConversation()
        self.context = context
    }

    /// Bring in a new context and immediately ask a specific question —
    /// used when the entry point already knows what to ask (e.g. "analyze
    /// this record"). Appends to the same shared conversation.
    func ask(_ text: String, context: AgentContext?, environment: APIEnvironment) {
        startNewConversation()
        self.context = context
        draft = text
        send(environment: environment)
    }

    /// 开一段新的对话。当前这段不会丢——它已经在目录里。
    func startNewConversation() {
        activeTask?.cancel()
        sessionID = nil
        streamIndex = 0
        continuationToken = nil
        messages = []
        activityLog = []
        state = .idle
    }

    /// 打开一段历史对话：把 Eve 那边的事件从头重放回来。
    ///
    /// 内容不在我们库里，只有 Eve 有。重放不到时给一句明确的话，
    /// 而不是让用户对着空白页猜。
    func open(_ session: AgentSessionSummary, environment: APIEnvironment) {
        activeTask?.cancel()
        sessionID = session.eveSessionID
        streamIndex = 0
        continuationToken = nil
        messages = []
        activityLog = []
        state = .streaming
        isReplaying = true

        let client = EveClient(environment: environment)
        self.client = client
        activeTask = Task { [weak self] in
            let events = await client.resume(sessionID: session.eveSessionID, from: 0)
            do {
                for try await event in events { self?.consume(event) }
                self?.isReplaying = false
                if self?.messages.isEmpty == true {
                    self?.fail("这段对话的内容已不可用")
                }
            } catch {
                self?.isReplaying = false
                self?.fail("这段对话的内容已不可用")
            }
            await self?.sessions?.touch(session, environment: environment)
        }
    }

    func retryLast(environment: APIEnvironment) {
        guard let lastUserText else { return }
        draft = lastUserText
        messages.removeAll { $0.text == lastUserText && $0.isUser }
        send(environment: environment)
    }

    /// 正等着你回答的那次反问，没有就是 nil。
    var pendingQuestion: AgentQuestion? {
        guard case let .awaitingAnswer(request) = state else { return nil }
        return AgentQuestion(request: request)
    }

    /// 点选项作答。发回去的是选项自己的 id，不是写死的 "approve"。
    func answer(optionID: String?, label: String, environment: APIEnvironment) {
        guard case let .awaitingAnswer(request) = state else { return }
        messages.append(AgentMessage(text: label, isUser: true))
        lastUserText = label
        deliverAnswer(
            requestID: request.requestID,
            optionID: optionID,
            text: optionID == nil ? label : nil,
            environment: environment
        )
    }

    func send(environment: APIEnvironment) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        // 有反问悬着的时候，打的字是这次提问的答案，不是新一轮对话。
        // 另起一轮模型就收不到答案，会一直卡在等待里。
        if case let .awaitingAnswer(request) = state {
            messages.append(AgentMessage(text: text, isUser: true))
            lastUserText = text
            deliverAnswer(requestID: request.requestID, optionID: nil, text: text, environment: environment)
            return
        }
        messages.append(AgentMessage(text: text, isUser: true))
        lastUserText = text
        let requestText = requestMessage(for: text)
        state = .streaming
        let client = EveClient(environment: environment)
        self.client = client
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            do {
                let events: AsyncThrowingStream<EveEvent, Error>
                if let sessionID = self?.sessionID {
                    events = try await client.send(sessionID: sessionID, message: requestText, from: self?.streamIndex ?? 0)
                } else {
                    events = try await client.start(message: requestText)
                    let newID = await client.currentSessionID
                    self?.sessionID = newID
                    // 登记进目录，否则这段对话重启后就再也找不到了。
                    if let newID {
                        await self?.sessions?.record(
                            eveSessionID: newID,
                            title: AgentSessionTitle.from(text),
                            environment: environment
                        )
                    }
                }
                for try await event in events { self?.consume(event) }
            } catch {
                self?.fail(error.localizedDescription)
            }
        }
    }

    func approve(_ request: EveInputRequest, environment: APIEnvironment) {
        respond(request, approved: true, environment: environment)
    }

    func cancelApproval(_ request: EveInputRequest, environment: APIEnvironment) {
        respond(request, approved: false, environment: environment)
    }

    func stop() {
        activeTask?.cancel()
        state = .idle
    }

    func undo(_ activity: AgentActivity, environment: APIEnvironment) {
        // 新建类有确定的删除目标，直接调接口。让模型去「撤销上一次变更」并不可靠——
        // 它会转而反问，撤销就落空了。
        if activity.undoTarget != nil {
            activeTask = Task { [weak self] in await self?.undoDirectly(activity) }
            return
        }
        guard let sessionID else { return }
        activityLog.removeAll { $0.id == activity.id }
        let client = EveClient(environment: environment)
        state = .streaming
        activeTask = Task { [weak self] in
            do {
                let events = try await client.send(
                    sessionID: sessionID,
                    message: "撤销上一次计划变更",
                    from: self?.streamIndex ?? 0
                )
                for try await event in events { self?.consume(event) }
            } catch {
                self?.fail(error.localizedDescription)
            }
        }
    }

    /// 直接删除 Agent 刚创建的对象。删除失败时保留台账条目——否则撤销入口消失，
    /// 数据却还在。
    func undoDirectly(_ activity: AgentActivity) async {
        guard let target = activity.undoTarget, let repository else { return }
        do {
            switch target {
            case let .task(taskID): try await repository.deleteTask(taskID: taskID)
            case let .record(recordID): try await repository.deleteRecord(recordID: recordID)
            }
            activityLog.removeAll { $0.id == activity.id }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func deliverAnswer(
        requestID: String,
        optionID: String?,
        text: String?,
        environment: APIEnvironment
    ) {
        guard let sessionID else { return }
        let client = EveClient(environment: environment)
        self.client = client
        state = .streaming
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            do {
                try await client.respondToInput(
                    sessionID: sessionID, requestID: requestID, optionID: optionID, text: text
                )
                let events = await client.resume(sessionID: sessionID, from: self?.streamIndex ?? 0)
                for try await event in events { self?.consume(event) }
            } catch {
                self?.fail(error.localizedDescription)
            }
        }
    }

    private func respond(_ request: EveInputRequest, approved: Bool, environment: APIEnvironment) {
        guard let sessionID else { return }
        let client = EveClient(environment: environment)
        state = .streaming
        activeTask = Task { [weak self] in
            do {
                try await client.respondToApproval(sessionID: sessionID, approvalID: request.requestID, approved: approved)
                let events = await client.resume(sessionID: sessionID, from: self?.streamIndex ?? 0)
                for try await event in events { self?.consume(event) }
            } catch {
                self?.fail(error.localizedDescription)
            }
        }
    }

    func consume(_ event: EveEvent) {
        streamIndex = max(streamIndex, event.streamIndex)
        switch event.type {
        case .sessionStarted:
            break
        case .inputRequested:
            let requests = event.inputRequests
            guard let first = requests.first else { break }
            if let question = AgentQuestion(request: first) {
                // 反问进对话流，用户在输入框或选项里回答。
                messages.append(AgentMessage(text: question.prompt, isUser: false))
                state = .awaitingAnswer(first)
            } else {
                // 一个事件可能带来整批审批，全部留住；只认第一条会让整轮 parked。
                beginApprovalBatch(requests.filter { AgentQuestion(request: $0) == nil })
                state = .awaitingApproval(first)
            }
        case .messageReceived:
            // 只在重放时还原用户消息。实时发送已经本地 append 过了。
            guard isReplaying,
                  let text = event.userMessageText,
                  !text.isEmpty else { break }
            messages.append(AgentMessage(text: AgentPromptText.userVisible(text), isUser: true))
        case .actionResult:
            guard let outcome = AgentToolOutcome(event: event) else { break }
            state = .applied
            if let activity = outcome.activity { activityLog.insert(activity, at: 0) }
        case .messageCompleted:
            if let message = try? JSONDecoder().decode(EveMessageCompleted.self, from: event.data),
               AgentResponseText.shouldDisplay(finishReason: message.finishReason),
               let text = message.message {
                let cleaned = AgentResponseText.clean(text)
                if !cleaned.isEmpty { messages.append(AgentMessage(text: cleaned, isUser: false)) }
            }
        case .sessionWaiting:
            continuationToken = event.continuationToken
            if case .streaming = state { state = .idle }
        case .turnCompleted:
            if case .streaming = state { state = .idle }
        default:
            break
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
    }
}

private struct EveMessageCompleted: Decodable {
    let finishReason: String?
    let message: String?
}

struct AgentActivity: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let occurredAt: Date
    let canUndo: Bool
    /// 新建类操作的撤销对象。既有的「修改」类走 undo_operation，没有撤销对象。
    let undoTarget: AgentUndoTarget?

    init(
        id: UUID,
        title: String,
        occurredAt: Date,
        canUndo: Bool,
        undoTarget: AgentUndoTarget? = nil
    ) {
        self.id = id
        self.title = title
        self.occurredAt = occurredAt
        self.canUndo = canUndo
        self.undoTarget = undoTarget
    }
}

/// 撤销「Agent 新建」的目标。undo_operation 做的是字段级还原，新建没有可还原的
/// 前值，所以撤销走的是删除。
enum AgentUndoTarget: Equatable, Sendable {
    case task(UUID)
    case record(UUID)
}

/// 一次工具调用的结果。
///
/// 之前这里不区分工具：任何 action.result 都被记成「已更新家庭计划 · 可撤销」，
/// 于是用户只是问一句，台账上也会多出一条指向不存在变更的撤销入口。
struct AgentToolOutcome: Equatable, Sendable {
    let toolName: String
    let summary: String
    let activity: AgentActivity?

    /// 只读工具：调用它们不改变任何事实，不该出现在「最近处理」里。
    static let readOnlyTools: Set<String> = [
        "get_pregnancy_context", "list_tasks", "list_records",
        "get_guidance", "echo_context", "preview_task_change",
    ]

    init?(event: EveEvent) {
        guard event.type == .actionResult,
              let payload = try? JSONDecoder().decode(EveActionResultPayload.self, from: event.data)
        else { return nil }
        let result = payload.result
        toolName = result.toolName
        summary = result.output.summary ?? ""

        if Self.readOnlyTools.contains(toolName) {
            activity = nil
            return
        }

        let data = result.output.data ?? [:]
        switch toolName {
        case "create_task":
            let title = data["title"] ?? "新的待办"
            activity = AgentActivity(
                id: UUID(),
                title: "已添加待办「\(title)」",
                occurredAt: .now,
                canUndo: true,
                undoTarget: data["task_id"].flatMap(UUID.init(uuidString:)).map(AgentUndoTarget.task)
            )
        case "create_record":
            activity = AgentActivity(
                id: UUID(),
                title: "已记录",
                occurredAt: .now,
                canUndo: true,
                undoTarget: data["record_id"].flatMap(UUID.init(uuidString:))
                    .map(AgentUndoTarget.record)
            )
        case "delete_task", "delete_record":
            // 撤销本身不该再产生一条可撤销的台账。
            activity = nil
        default:
            activity = AgentActivity(
                id: UUID(),
                title: "已更新家庭计划",
                occurredAt: .now,
                canUndo: true
            )
        }
    }
}

private struct EveActionResultPayload: Decodable {
    struct Result: Decodable {
        struct Output: Decodable {
            let summary: String?
            let data: [String: String]?
        }
        let toolName: String
        let output: Output
    }
    let result: Result
}
