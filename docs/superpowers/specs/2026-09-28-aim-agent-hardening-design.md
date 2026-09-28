# AIM 对话 Agent 补全 设计规格

2026-09-28

## 1. 目标

AIM 现在「能聊」，但不是一个完善的 agent：几条端到端链路没接上（快捷入口的上下文、写入后的刷新、指派与撤销），确认卡文案全是「收录」，模型开局对用户一无所知，界面缺停止／重试／撤销，WebView 的固有问题（重载丢草稿、白屏、字号）也没处理。

本规格把审计出的约 30 个问题收拢成三期，每期可独立上线、独立验证：

1. **链路修通**——已有功能真正能用
2. **Agent 能力**——让它像一个知道你是谁的助手
3. **体验打磨**——停止／重试／撤销、WebView 不像 WebView、清理死代码

## 2. 已确认的决策

- **继续用 assistant-ui + WKWebView，不回原生。** 重新调研过 SwiftUI 生态：Stream 的 `stream-chat-swift-ai` 许可证与其后端绑定；exyte/Chat 是消息语义，已经因为这个原因移除过一次；swift-ai-sdk 类移植只有状态层，且说的是 AI SDK 流协议不是 Eve 事件流；assistant-ui 的 native 版要求 React Native。原生等于自建整套 agent UI，而约八成问题与 UI 技术无关。
- **不做 bundle 本地加载。** `AgentWebScheme.swift` 注释记录过：`WKURLSchemeHandler` 会把 Eve 的长连接流缓冲到结束才交给 `fetch`。离线体验改由原生错误页 + 网关缓存头解决（§5.4）。
- **快捷入口 = 新对话 + 输入框上方的上下文标签。** 「正在看：番茄炒蛋 ✕」，用户自己提问；上下文随首条消息隐式发送，不出现在气泡里；点 ✕ 去掉。例外：「让 Agent 分析当前记录」打开后自动发送；首页 AIM 按钮开普通新对话、不带标签。
- **写操作分档按「能否一键撤回、是否影响他人」：**

| 档位 | 工具／操作 |
| --- | --- |
| 直接执行，事后可撤销 | 新建待办、新建记录、完成待办、撤销 |
| 执行前确认 | 延期／改期、指派给家人、修改或删除已有记录、修改待办标题／描述、记录孕期信息、收录到资料库 |

  相对现状的变化：完成待办、撤销从「确认」挪到「直接执行」。档位仍只在服务端 `DIRECT_EXECUTION_TOOLS` 声明，Eve 侧的 `approval: always()` 与之保持一致。

- **生产模型仍为 DeepSeek `deepseek-chat`。**
- **逐周指导内容的补写不在本规格**（现仅覆盖 5–12 周与 18 周），与首页改版的内容工作一起规划。

## 3. 第一期：链路修通

### 3.1 撤销统一到操作编号

现状：`undo_operation` 需要 `changeId`，但没有任何工具返回它；`delete_task` / `delete_record` 名义上只用于撤销刚新建的条目，服务端却不做任何限制，且不需要确认——模型可以不经确认删掉用户任意一条待办或记录。

改为：

- 每个写工具的结果里已经有 `operationId`，`ToolInvocation` 也按 `(session_id, call_id)` 存了 `tool_name` 与 `result`。`undo_operation` 改为只收 `operationId`，服务端查出原调用，按 `tool_name` 执行反向操作：
  - `create_task` → 删除该待办
  - `create_record` / `create_knowledge` → 删除该记录
  - `update_task`（complete / delay / schedule）、`assign_task` → 用该次写入产生的 task change 走 `undo_change`
  - `record_pregnancy_fact` → **本期不支持撤销**，返回「孕期信息不能撤销，直接告诉我正确的值即可」。孕期事实是按来源优先级相互覆盖的证据账本，撤销需要改覆盖规则，且该工具本就在「执行前确认」档。
- 为此，`complete_task`、`reschedule_task`、`assign_task` 的结果 `data` 增加 `change_id`。
- `tool_invocations` 增加 `account_id`、`family_id`、`pregnancy_id`、`undone_at`（迁移 `0009`）。撤销时校验原调用属于当前账号、目标仍在当前 pregnancy 范围内；`undone_at` 已有值时直接返回成功（幂等）。历史数据这几列为空，不能经公开接口撤销。
- 待办在原调用之后又被改过时，撤销返回冲突「这项待办之后又被改过，不能直接撤销」。
- `delete_task` / `delete_record` 两个 Eve 工具**不再暴露给模型**（`disableTool`），对应内部接口只供撤销用例调用。
- 新增公开接口 `POST /api/v1/agent/operations/{operation_id}/undo`，给网页卡片上的「撤销」按钮用，与 `undo_operation` 共用同一应用层用例。
- `undo_operation` 移出 `always()`，加入 `DIRECT_EXECUTION_TOOLS`；`update_task` 的 `complete` 动作同样直接执行——`update_task` 拆成 `complete_task`（直接）与 `reschedule_task`（`schedule` / `delay`，需确认），因为 Eve 的审批档位按工具而非按参数。

### 3.2 确认卡显示真实内容

- 为每个需确认的工具注册渲染器：`reschedule_task`（待办标题，原日期 → 新日期）、`assign_task`（待办标题 → 家人称呼）、`record_pregnancy_fact`（项名：原值 → 新值）、`create_knowledge`（已有）、以及第二期新增的记录／待办修改与删除工具。
- 卡片上的待办标题、成员称呼等展示信息由网页凭 ID 调公开 API 查出，**不采信模型参数里的描述**。
- 按钮文案按工具区分（「确认改期」「确认指派」「确认收录」…／「取消」），`ToolGroup.tsx` / `ToolCard.tsx` 里写死的「收录」全部去掉。
- `ToolGroupActions` 只在本条消息有待确认项时渲染：`ApprovalBatchProvider` 的登记带上 message id，`pendingCount` 按消息计。
- 提交失败（`approvals.tsx` 现在只 `console.error`）在卡片上显示错误和「重试」。
- 删除 `preview_task_change` 工具，以及 `instructions.md` / `adjust-pregnancy-plan` 技能里「写之前先 preview」的要求——确认卡本身就是预览。

### 3.3 原生 ↔ 网页的桥

- `NativeContext` 增加 `entry`：
  - `{ mode: "resume" }`——AIM 标签页，接回上一段
  - `{ mode: "new", pageContext?: { title, summary } }`——快捷入口
  - `{ mode: "new", pageContext, autoSend: string }`——「分析当前记录」
- 网页按 `entry` 决定接回还是新开；有 `pageContext` 时在输入框上方显示标签。
- 页面上下文走 Eve 的 `clientContext`：`useEveAgentRuntime` 的 `prepareSend` 在标签存在期间给**每一轮**附上 `{ page: { title, summary } }`。它只进入该轮的模型调用、不写入会话历史，所以气泡里不会出现，也不需要隐藏标记；用户点 ✕ 后不再附带。重新打开一段历史对话时标签不恢复。
- **写入后刷新**：网页从事件流里看到写工具的 `action.result` 为 `completed` 就立即调用 `notifyTurnFinished({ kinds: ["task" | "record" | "knowledge"] })`，**不等整轮结束**——用户看到卡片上的「已添加」就会切回首页，那时模型可能还在写收尾的话。原生 `TimelineStore`、`RecordsStore`、`LibraryStore` 订阅 `.aimAgentTurnFinished`，按 kind 各自 `load()`。
- **跳转**：卡片上的「查看」调用 `openNative`；`AgentView.onNavigate` 在自己的 `NavigationStack` 里推入 `TaskDetailView` / `RecordDetailView` / 资料详情。
- **标签页与快捷入口的同步**：快捷入口仍是独立的 `fullScreenCover` WebView。AIM 标签页重新出现时，原生调用 `__aimOnAppear__`；网页若发现本地存储的最近会话已不是当前这段、且当前不在生成中、输入框为空，就切到最近那段。
- 「让 Agent 分析当前记录」（`RecordDetailView.swift`）不再调用 `AgentStore.ask`，改为以 `autoSend` 打开对话面。

### 3.4 工具层修正

- `get_pregnancy_context` 增加 `members: [{ member_id, display_name, role }]`，以及当前账号自己的 `member_id`。
- `create_record` 的参数按类型平铺并在描述里写明各类型该填哪些：`symptom` 要求 `symptoms`（非空）与 `severity`（1–5）；`checkup` 的四个文本字段缺省为空串、指标只能取 `weight_kg` / `systolic` / `diastolic` / `fasting_glucose` / `hemoglobin`；`note` 要求 `content`。不用判别联合是因为 OpenAI 兼容的函数调用要求顶层为 object。缺字段在工具内先拦下，中文错误回到模型手里。
- **时间参数一律为北京时间的墙上时刻**（`YYYY-MM-DDTHH:mm`，不带时区），由工具补 `+08:00`；带 `Z` 或偏移的串校验失败。验证中发现模型会把「明天下午三点」写成 `T15:00:00Z`，落库后晚 8 小时。
- `resolve-session` 在账号尚无孕期档案时返回 `pregnancy_id: null`；工具层统一抛出中文错误「还没有建立孕期档案，请先在 App 里填写预产期或末次月经」，替换 `session-context.ts` 里的英文消息。

### 3.5 运行保障

- 新增环境变量 `AIM_DEPLOYMENT`，只在 `compose.prod.yaml` 里设为 `production`（不能用 `NODE_ENV`：Dockerfile 对本地栈也设了 `production`）。它为 `production` 时，若 `EVE_USE_MOCK_MODEL` 不是 `0` 或缺少模型凭证，Agent 运行时**启动即失败**，不再退回 mock。本地 compose 保持默认 mock。
- `apps/agent-web` 的 `eve` 升到与运行时一致的 `0.47.2`，`@assistant-ui/eve` 同步到兼容版本并锁定。

### 3.6 验证

本地栈逐场景：完成待办后撤销；指派给爸爸并确认；一轮里三个待确认项各自显示正确内容；从菜谱页快捷入口提问、模型知道是哪道菜；AIM 新建待办后首页自动出现；无孕期档案账号得到中文引导；分析记录打开即可见。服务端撤销用例（各 tool_name 的反向、跨账号拒绝、重复撤销幂等）与权限范围写单元测试。

## 4. 第二期：Agent 能力

### 4.1 每轮注入用户简报

- 新增内部接口 `/internal/agent-tools/session-brief`，返回：今天日期与星期（Asia/Shanghai）、孕周+天、预产期与剩余天数、当前用户身份与称呼、家庭成员名单、今日与逾期待办数及最重要的至多 5 条标题、最近 7 天症状／产检记录的条数与类型。
- Eve 侧用 `defineDynamic(defineInstructions(...))` 在 `turn.started` 解析，作为 system 角色注入。每轮而非每段对话：跨天续聊时日期和孕周不会过期。
- 静态 system 指令排在前、动态简报排在后，便于提供方复用前缀缓存。
- 无孕期档案时简报写明「尚未建立孕期档案」。

### 4.2 已审核内容可读

- 新增 `read_content({ collection })`，collection ∈ `safety-rules` / `nutrition` / `preparation` / `hangzhou`，经内部接口读 `content/` 下的版本化内容。
- 系统指令硬规则：**用户提到身体症状时，先读 `safety-rules` 对照；命中红旗症状，第一句就建议尽快就医。**
- `get_guidance` 去掉写死的 `CN-ZJ-HZ`，地区取自家庭资料，缺省为杭州。

### 4.3 读工具瘦身，补齐常用操作

- `list_tasks`：默认只返回未完成；参数 `status`、`due_from` / `due_until`、`limit`（默认 30）；结果加 `description`。
- `list_records`：参数 `type`、`occurred_from` / `occurred_until`、`limit`（默认 20），按时间倒序。
- 新增需确认的写工具：`update_record`、`remove_record`（只能删当前账号可见的记录）、`edit_task`（标题／描述）。均可经 §3.1 撤销：`update_record` / `edit_task` 的结果记录修改前的字段值；记录本就是软删除（`records.deleted_at`），`remove_record` 的撤销即清空 `deleted_at`，领域层补一个恢复用例。
- `get_pregnancy_context` 同时返回已记录的孕期信息（facts）。

### 4.4 精简工具

- `disableTool`：`echo_context`、Eve 内建 `agent` / `todo` / `task_update` / `task_cancel`。
- 删除 `pregnancy-expert` 子 agent（它没有任何数据工具），同步修改 `adjust-pregnancy-plan` 技能中「交给子 agent」的步骤。
- 保留 `ask_question`，第三期补界面。

### 4.5 重写系统指令

`instructions.md` 按五段组织：身份与语气；如何使用简报；写操作档位（与 §2 表格一致，直接执行的操作做完后一句话告知并提示可撤销）；安全规则（不诊断、症状先查红旗、区分「你记录的」与「我的判断」）；输出格式（保留现有的纯文本约束）。

### 4.6 评测

- 修复 `evals/plan-change.eval.ts`、`runtime-gate.eval.ts`：改用合法 Bearer 票据。
- 新增真实模型场景评测（环境变量开启，不进 `make test`）：「产检做完了」直接完成；「把下周产检推到周五」出改期确认；「让老公去买待产包」指派给爸爸；「今天有点见红」首句建议就医；「撤销刚才那个」成功；跨天续聊日期孕周正确。

## 5. 第三期：体验打磨

### 5.1 对话操作

- 生成中发送钮变为停止（`ComposerPrimitive.Cancel` → Eve `/cancel`）。
- 失败的一轮在错误提示下给「重试」，重发上一条用户消息；`SessionRecovery` 的失败文案同样带按钮。
- 助手消息下方加复制（`ActionBarPrimitive.Copy`）。
- 不做「重新生成」：Eve 会话不支持分叉。

### 5.2 已执行卡片：查看与撤销

- `create_task`、`create_record`、`create_knowledge`、`complete_task` 及已确认执行的写操作，执行后卡片显示「已创建／已完成／已改期…」、标题与时间，附「查看」「撤销」。撤销走 §3.1 的公开接口，成功后卡片变「已撤销」。
- 为 `create_record` 补专用卡片（现为通用卡）。
- 修正 `CreateTask.tsx` 读 `args.detail`、工具参数实为 `description` 的问题。

### 5.3 回答模型的提问

- 为 `ask_question` 注册渲染器：问题 + 选项按钮 + 自由输入。
- `eveTransport` 的 `respondAll` 从只支持 `approved` 扩展为可携带回答内容，经 Eve 的 `inputResponses` 送回。

### 5.4 WebView 不像 WebView

- **主题与票据变化不重载对话**：`App.tsx` 的接回 effect 只依赖账号键，不依赖整个 `context`；主题只切换根节点 class；票据更新只替换请求头。只有账号变化才重新接回。
- **Dynamic Type**：根字号取 `font: -apple-system-body`，`styles.css` 中的固定 px 全部换成 rem／em，WKWebView 随系统字号缩放。
- **加载与离线**：`AgentWebView` 实现 `WKNavigationDelegate`；页面发出 ready 之前原生显示骨架；导航失败显示原生错误页与「重试」。
- **网关缓存**：nginx `location /agent/` 下带哈希的静态资源 `Cache-Control: public, max-age=31536000, immutable`，`index.html` `no-cache`。

### 5.5 空状态与历史

- 空状态显示 3–4 个可点的建议问题，由原生经 `NativeContext.suggestions` 传入：「第 N 周要注意什么」「今天的待办有哪些」「记一下今天的症状」，有逾期时加「帮我处理逾期的事」；带页面上下文时换成与该页相关的问题。
- `HistoryPanel` 支持左滑删除，删除时同时调用 Eve `/reset` 结束该会话；每轮结束 `touchSession` 更新 `last_active_at`；标题截断改回 40 字（`sessions.ts`）。不做重命名与分页。

### 5.6 清理

- 删除 `AgentSessionStore`、`AgentSessionListView`、`AgentDiffSheet`、`AgentQuestion`、`AgentChangePreview` 及对应的 6 个测试文件。
- `AgentStore` 只保留「本次从哪个入口进来、带什么上下文」，更名 `AgentEntry`；所有 `agentStore.focus(context:)` 调用点改为构造 `AgentEntry`。

### 5.7 验证

模拟器逐项：停止生成；断网打开见错误页并可重试；系统字号调到最大；深色模式来回切换草稿仍在；已创建卡片撤销；回答模型提问；左滑删除历史。`apps/agent-web` 补组件测试覆盖卡片各状态（待确认、提交中、失败可重试、已执行、已撤销）。

## 6. 风险

- **`@assistant-ui/eve` 仍是 0.0.x。** 升级到与 eve 0.47.2 兼容的版本可能改 API；锁版本，第一期先做升级并跑通现有场景再动其它。
- **拆分 `update_task`** 会让旧会话里的历史工具调用找不到渲染器，走通用卡兜底即可。
- **页面上下文不进历史**：`clientContext` 不持久化，续聊历史对话时模型看不到当初的页面内容，只能从它自己当时的回复里推断。这是有意的取舍——页面摘要可能包含大段资料，写进历史会持续占用上下文。
- **待办的删除是硬删除。** 撤销「新建待办」即删除它，这没有问题；但本规格不给模型「删除已有待办」的能力——用户想去掉一项待办时，模型建议改期或由用户在原生页面删除。
