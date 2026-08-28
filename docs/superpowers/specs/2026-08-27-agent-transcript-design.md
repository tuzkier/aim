# AIM 对话面：换成 assistant-ui 的 Agent 事件流

2026-08-27

## 问题

用户让 AIM 把几道菜收进菜谱：确认卡弹出、点了「收录」、卡片消失，然后什么都没
发生——菜没入库，那段对话回头看还少了一截。

排查下来是两个独立的原因叠在一起。

### 一、运行时不结算审批批次（真正的根因）

模型在同一轮里发起多个需要审批的工具调用时，Eve 把它们打成**一个批次**下发
（`input.requested` 的 `requests` 是数组）。`eve@0.37.1` 从不结算这个批次。

本地栈对照实测（三道菜，三条响应放在同一个请求里发回）：

| | 0.37.1 | 0.44.1 |
|---|---|---|
| `action.result` | **0** | **3** |
| `input.requested` | 2（模型重新提议了一轮） | 1 |
| `input.resolved` | **不存在这个事件** | **1** |
| `approval.settled` | 3 | 3 |

旧版三条审批全部 `approved`，但批次从未 resolve，工具一条都不执行。已升级到
0.44.1 修复，三道菜全部落库并各自拿到 `record_id`。

单个审批在 0.37.1 下是正常的——所以这个缺陷只在「一轮里提议多件事」时暴露。

### 二、客户端只认批次里的第一条

`AgentStore.consume` 取 `event.inputRequests.first`，其余静默丢弃；
`AgentSheetState.awaitingApproval(EveInputRequest)` 也只能装一个请求。第 2、3 张
确认卡从未出现过，点掉第一张后 `state` 转 `.streaming`，卡片按设计消失，而 parked
的那一轮把模型输出扣住不发——这就是「界面消失」和「对话少一截」。

根子是**把审批建模成了会话级的单槽状态**。审批属于某一次工具调用，不属于会话。

### 三、看不到执行过程

Eve 协议有 31 种事件，App 的解析器只认 12 种、`consume` 只处理 6 种。
`message.appended`（助手文字的流式增量）、`actions.requested`（工具开始执行）、
`turn.failed` / `session.failed`（失败）全落进 `default: break`。所以界面上只有一句
「正在整理回答…」——不是渲染没做好，是数据在 store 就被扔了。

现有的 `ExyteChat` 是纯消息控件，`Message(id:user:status:text:)` 里没有位置放步骤、
思考和审批卡。不是配置不当，是形态不对。

## 方案

### 为什么不是原生自建

先在 SwiftUI 生态找过：唯一真正面向 agent 的库（Stream 的 `stream-chat-swift-ai`）
许可证要求使用者是 Stream.io 付费客户；其余（SwiftyChat、exyte/Chat）都是消息语义，
换过去解决不了问题。

扩大到跨端之后发现了直接可用的东西：**`@assistant-ui/eve` 是 assistant-ui 官方给
Eve 运行时写的适配器**，peer 依赖 `eve >= 0.32.0`，而 `eve/react` 是 Eve 自带的
浏览器客户端。链路是现成的：

```
eve/react (useEveAgent)  →  @assistant-ui/eve (useEveAgentRuntime)  →  @assistant-ui/react
```

更要紧的是它的建模：审批挂在**工具调用 part 自身**上（`state === "approval-requested"`、
`part.approval`、`part.toolMetadata.eve.inputRequest`）。三道菜就是三个 part 各自带
审批态，各自独立批准。上面第二个缺陷在这个结构里**无法表达**。

### 形态

WKWebView 承载一个 React 应用，产物打进 App bundle 本地加载（不远程加载——线上仍是
明文 HTTP）。

消息流是异质的：文字气泡、可折叠的思考、工具步骤行、内联审批卡按发生顺序排在同一条
流里。审批**内联**而不是浮层——批次里有三道菜时，浮层要么排队弹三次、要么像现在这样
丢掉两个。

### 按 toolName 注册渲染器

`create_knowledge` 出菜谱卡、`create_task` 出待办卡、未注册的落通用卡。只读工具
（`list_tasks`、`get_guidance` 等）不进「最近处理」台账，但**要**在流里显示为步骤行——
「它查了什么」正是用户想看到的过程。

### 原生桥

- **会话票**：原生注入，Web 侧不做登录
- **跳转**：点流里的资料库条目回到原生 Library/Records 页
- **主题**：跟随原生浅色/深色

## 影响

删除 `ExyteChat` 依赖、`AgentChatAdapter.swift`，以及 `AgentView` 的聊天部分。
`KnowledgeApprovalSheet` / `KnowledgePreview` 及其测试用 React 重写。`AgentStore`
只保留会话目录与上下文，事件消费移交适配器。

会话列表（`AgentSessionListView`）暂留原生。

## 风险

**`@assistant-ui/eve` 是 v0.0.14。** 早期版本，API 会变。这是最大的风险，需要锁版本
并留好回退路径。

**新增前端工具链。** 仓库此前没有任何 web 构建，iOS 构建要多一步产物拷贝。

**WebView 的固有问题**：键盘、滚动惯性、Dynamic Type、文本选择都要单独处理。

## 验证

- 本地栈起三道菜的场景，三张卡各自独立批准，三条 `action.result` 全部完成
- 助手文字边流边显（`message.appended` 生效）
- `turn.failed` 在界面上有可见的失败态
- 断网时 WebView 仍能加载外壳并给出明确错误，而不是白屏

## 未决

- 升级到 `eve@0.47.2` 被 `disableTool()` 的新校验挡住：本仓库禁用了 8 个内建工具
  （`bash`、`write_file` 等），新版报 `disables a slot with no lower-precedence source`。
  删掉禁用文件等于把 `bash` 放给 agent，需要先查清新版槽语义。
- 鉴权修复与 eve 升级都尚未部署到生产。
