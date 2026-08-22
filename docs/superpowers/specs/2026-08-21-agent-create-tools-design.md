# 把 App 能力开成 Agent 工具：新建待办与新建记录

日期：2026-08-21

## 背景

产品设计里 Agent 应当能执行 App 自身的业务能力（ADR-0004「统一 Agent 运行时与工具网关」、
时间线重设计 §6）。当前实现只开了一半：

| App 能力 | Agent 工具 | |
| --- | --- | --- |
| 看今天 / 计划 | `get_pregnancy_context`、`list_tasks` | 有 |
| 看记录 | `list_records` | 有 |
| 完成 / 延期 / 排期 | `update_task` | 有 |
| 指派 | `assign_task` | 有 |
| 撤销任务变更 | `undo_operation` | 有 |
| 查孕周指导 | `get_guidance` | 有 |
| **新建待办** | 无 | **缺** |
| **新建记录** | 无 | **缺** |
| 改 / 删记录 | 无 | 缺 |
| 家庭成员 / 邀请 | 无 | 缺 |

用户问「帮我加个待办」时，模型没有可用工具，只能绕开或者凭空宣称已添加——实际什么都没发生。

## 范围

本轮只做 `create_task` 和 `create_record`，以及它们的撤销路径。
改 / 删记录、家庭成员、邀请留待后续。

## 权限档位

按时间线重设计 §6.1，「建普通待办、整理记录」属于**直接执行**档：不打断对话，
时间线直接出现并带 `Agent 调整` 来源标记，深色 toast 停留 5 秒提供「撤销」。

这意味着 Eve 侧这两个工具**不使用** `approval: always()`——与现有写工具的做法不同。
后端不强制审批（`_run(write=True)` 只做幂等与归属校验），所以放开是 Eve 侧的改动。

## 撤销

「直接执行」档必须有兜底。现有 `undo_operation` 做的是**字段级还原**——把任务字段
还原成 `change.before` 的快照。新建没有 before 状态，因此它撤销不了创建。
§6.1 对这一档写的撤销路径是「走任务自身的删除」。

- **记录**：已有 `DELETE /api/v1/pregnancies/{id}/records/{record_id}`，直接复用。
- **任务**：删除能力**完全不存在**——没有路由、没有领域方法、客户端也没有。本轮新建。

采用**硬删除**（已确认）。代价是任务的 `task_changes` 会被级联删除，审计轨迹一并消失；
选择硬删除是为了避开软删除所需的迁移与全量查询改造。

## 后端改动

**公开 API**

- `DELETE /api/v1/pregnancies/{pregnancy_id}/tasks/{task_id}` → 204。
  校验任务属于该孕期、调用方是家庭活跃成员。硬删除，级联清除 `task_changes`。

**领域层**

- `PlanningUnitOfWork.repository` 增加 `delete_task(task_id)`。
- 新增 `delete_task` 命令，复用现有的归属校验（对齐 `undo_change` 的写法）。

**工具网关**（`/internal/agent-tools/`）

| 端点 | 说明 |
| --- | --- |
| `create-task` | 入参 `title`、`description?`、`due_at?`。`source_type=agent`、`changed_by_actor_type=agent`，让时间线能打来源标记 |
| `delete-task` | 入参 `task_id`。供撤销使用 |
| `create-record` | 入参与公开记录 API 的 `RecordDraft` 一致 |
| `delete-record` | 入参 `record_id`。供撤销使用 |

四者都走现有 `_run(..., write=True)`，继承幂等（`session_id` + `call_id`）与归属校验。

## Eve 改动

新增 `agent/tools/create_task.ts`、`create_record.ts`、`delete_task.ts`、`delete_record.ts`。

`create_task` 与 `create_record` **不设** `approval`（直接执行档）；两个 delete 工具仅供
撤销链路调用，同样不需要用户再确认一次——撤销本身就是用户的意思表示。

工具返回体沿用 `toolResultSchema`，`data` 里带回新建对象的 id 与标题，供客户端渲染卡片与
toast。

## 客户端改动

**会话卡片**：现有 `AgentChangePreview` / `AgentDiffSheet` 只覆盖对已有任务的**修改**
（`preview_task_change` 的 complete / snooze / assign）。新增一种「已创建」卡片形态：
图标 + 「已添加待办 / 已记录」+ 标题 + 「撤销」文字按钮。

**toast**：复用 `AimToastMessage`（时间线完成任务已经在用），文案「已添加「<标题>」」，
`undoTitle` 为「撤销」，停留 5 秒。

**来源标记**：任务的 `changed_by_actor` 为 `agent` 时时间线已经会显示 `Agent 调整`
（`TaskItem.isAgentChanged` 已存在），后端只要把 `changed_by_actor_type` 写成 agent 即可，
客户端无需改动。

**撤销落回**：撤销后重新拉取时间线，与现有 `complete` 流程一致。

## 测试

**后端**

- `DELETE` 任务：成功 204；跨孕期 403；不存在 404；级联删除 `task_changes`。
- `create-task` 工具：写入的任务 `changed_by_actor_type == agent`；同一 `call_id` 重放返回同一结果（幂等）。
- `create-record` 工具：同上。

**Eve**

- `create_task` / `create_record` 无需审批即可执行（与 `update_task` 的 `always()` 形成对照）。

**客户端**

- 单元：新建结果 → 「已创建」卡片模型；撤销回调触发删除。
- UI：向 Agent 说「帮我加一个待办：产检预约」→ 时间线出现该任务且带 `Agent 调整` 标记 →
  toast 上点「撤销」→ 任务消失。

## 不做什么

- 不做软删除与归档。
- 不开放家庭成员、邀请、建孕期档案——它们分别涉及对外发送与医疗数据，风险档位不同。
- 不改动 `undo_operation` 的既有语义。
