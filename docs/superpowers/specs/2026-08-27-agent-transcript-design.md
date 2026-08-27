# AIM 对话面：从聊天控件换成 Agent 事件流

2026-08-27

## 问题

线上撞到的 bug 和界面观感是同一件事的两面。

用户让 AIM 把几道菜收进菜谱，确认卡弹出、点了「收录」、卡片消失，然后什么都没发生：
菜没入库，那段对话回头看还少了一截。

根因在 `AgentStore.consume`：

```swift
case .inputRequested:
    guard let request = event.inputRequests.first else { break }
```

模型在同一轮里发起多个 `create_knowledge`，Eve 把这一轮的审批打成**一个批次**下发
（`input.requested` 的 `requests` 是数组）。App 只取第一个，其余静默丢弃。而 Eve 的
批次要整批凑齐才结算——`buildResolvedInputBatch` 在批次不完整时返回 `undefined`，
那一轮就一直 parked，它「withheld model output」不发（对话少一截），批内工具一个
都不执行（菜一道也没存）。`AgentSheetState.awaitingApproval(EveInputRequest)` 只能
装一个请求，状态机本身就表达不了批次。

Eve 的协议注释把这条写在明处：consumers must correlate action lifecycles by call ID
rather than assume one event contains every call from an assistant step。`.first` 正是
它警告的那种假设。

更大的问题是这不是孤例。Eve 协议有 31 种事件，App 的解析器只认 12 种，`consume`
只处理 6 种：

- **解析器都不认识（落 `.unknown`）：** `reasoning.appended` / `reasoning.completed`、
  `step.started` / `step.completed` / `step.failed`、`action.partial`、`subagent.*` 四种、
  **`turn.failed` / `session.failed`**、authorization 与 compaction 各两种、
  `approval.candidate`、`result.completed`、`context.cleared`、`turn.cancelled`
- **认识但 `consume` 无 case、落 `default: break`：** `message.appended`（助手文字的
  流式增量）、`actions.requested`（工具开始执行）、`approval.settled`、`turn.started`、
  `session.completed`

所以「只显示『正在整理回答…』，看不到执行到哪一步」不是渲染没做好，是**流式增量和
步骤事件在 store 就被扔了**。失败事件同样收不到。

## 设计

分两层：先停止丢弃事件，再换渲染。只换控件不会让过程可见。

### 一、事件层

`EveEventType` 补齐到协议的 31 种。`consume` 去掉兜底的 `default: break`——改成穷举
`switch`，用不上的事件显式列出并写明为什么忽略。默认丢弃正是这次 bug 的成因，编译器
应当在协议新增事件时逼我们做一次决定。

按 `callId` 关联工具生命周期：`actions.requested` 开一条步骤、`action.partial` 补参数、
`action.result` 收口。不假设一个事件含一步的全部调用。

### 二、审批批次

`AgentSheetState.awaitingApproval(EveInputRequest)` 拆掉，改为 store 上的
`pendingApprovals: [EveInputRequest]`——一个批次里的请求全部在列。逐条回答，全部
有回音后才把响应发回 Eve 并恢复流。任意一条被否决仍然要把其余条目答完，否则批次
不结算。

这一条同时修掉三个症状，是首先要落地的部分。

### 三、渲染层

删除 `ExyteChat` 依赖（`XCRemoteSwiftPackageReference "Chat" 3.2.8`）与
`AgentChatAdapter.swift`。耦合只有两个文件，代价小。

`AgentMessage`（仅 `text` + `isUser`）换成 `AgentTranscriptItem`，异质行按发生顺序
排在同一条流里：

| 行 | 来源事件 | 形态 |
|---|---|---|
| 用户文字 | 本地 append / `message.received`（重放） | 右侧气泡 |
| 助手文字 | `message.appended` 增量 → `message.completed` 收口 | 左侧气泡，边流边显 |
| 思考 | `reasoning.appended` / `reasoning.completed` | 默认折叠的一行，可展开 |
| 步骤 | `actions.requested` → `action.result`，按 callId | 工具名 + running / 成功 / 失败 |
| 审批 | `input.requested`（kind=tool-approval） | **内联**卡，批次内逐条 |
| 反问 | `input.requested`（kind=question） | 内联选项，沿用现有 `AgentQuestion` |
| 失败 | `turn.failed` / `session.failed` / `step.failed` | 内联错误行 + 重试 |

审批从浮层 sheet 改为内联卡：批次里有三道菜时，浮层要么排队弹三次、要么像现在这样
丢两个；内联卡三张一起在流里，逐条处理，进度一目了然。这也顺带绕开了
`.sheet(item:)` 在 item 快速变更时会吞掉重新呈现的老问题。

只读工具（`AgentToolOutcome.readOnlyTools`）仍不进「最近处理」台账，但**要**在流里
显示为步骤行——「它查了什么」正是用户想看到的过程。

### 四、保留不动

`AgentStore` 的会话语义（`startNewConversation` / `open` 重放 / `sessions` 目录）、
`AgentContext`、`KnowledgePreview` 与其渲染逻辑都不动，只把 `KnowledgeApprovalSheet`
从 sheet 容器改成内联卡容器。

## 验证

- 单元测试：一个 `input.requested` 带 3 个审批 → 3 条都进 `pendingApprovals`；
  答完 2 条不发回 Eve，答完 3 条才发
- 单元测试：`message.appended` 连续增量 → 助手行文本累积，不重复成多条
- 单元测试：`actions.requested` 与 `action.result` 按 callId 配对，乱序到达也能配上
- 单元测试：`turn.failed` 产生失败行（此前完全收不到）
- 穷举 switch：协议新增事件时编译失败，而不是静默忽略
- `make ios-build` 与 `AimAppTests` 全过；UI 测试需先起本地 Compose 栈

## 未决

服务端 Eve trace 尚未核对——`~/.ssh/aim_deploy_ed25519` 连不上，缺 SSH 用户名。
trace 能确认那个批次此刻是否仍 parked 在会话里。不阻塞本设计，但值得回头验一次。
