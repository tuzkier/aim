# 孕期核心闭环 Implementation Plan

> **For Coding Agent:** REQUIRED WORKFLOW: execute this plan task-by-task, keep every task independently verifiable, and stop at the Eve validation gate if its required capabilities cannot be proven.

**Goal:** 从当前只有架构文档和交互原型的目录，建设可在 iOS Simulator、本地 FastAPI/PostgreSQL 与独立 Eve Runtime 上运行的孕期核心闭环。

**Architecture:** 业务事实由 FastAPI 轻量 DDD 模块化单体和 PostgreSQL 持有；Eve 只负责编排 Agent、Skills、Subagent、审批与流式会话，并通过受控 Tool API 修改业务事实；SwiftUI App 直接读取业务 API，并使用 Eve 原生会话流处理 Agent 交互。首个实施纵切覆盖“建立家庭与孕期 → 生成 Today/四周计划 → 完成、安排和分配任务 → Agent 预览并确认三项变更 → 同一计划与家庭成员同步”。

**Tech Stack:** SwiftUI、Observation、SwiftData、Swift OpenAPI Generator、Python、FastAPI、Pydantic 2、SQLAlchemy 2、Alembic、PostgreSQL、pytest、TypeScript、Node.js LTS、Eve、Zod、Vitest、Docker Compose、OpenTelemetry。精确运行时版本在 Task 1–2 验证后锁定。

---

## 0. 实施基线与硬边界

### Source of Truth

- 产品：`docs/plans/2026-08-13-pregnancy-ai-app-product-design.md`
- 旅程：`docs/plans/2026-08-13-pregnancy-user-journey-design.md`
- 技术架构：`docs/architecture/2026-08-14-mvp-technical-architecture.md`
- 目录：`docs/architecture/2026-08-14-monorepo-structure.md`
- ADR：`docs/architecture/adr/README.md`
- 交互：`prototype/src/Prototype.tsx`
- 交互验收：`prototype/audit/interaction-v2/audit.md`

### 不得偏离

1. 不把产品改造成聊天优先；Today 和计划是主入口。
2. 不让 Eve 或 iOS 连接 PostgreSQL。
3. 不让 Agent 文本成为业务成功凭证；只认可 FastAPI Tool Result。
4. 不把账号类型写死为妈妈或爸爸；身份属于 `FamilyMember`。
5. Agent 写操作必须经过“理解 → 预览 → 用户确认 → Tool 执行 → 可撤销”。
6. 不引入 Redis、Celery、Kafka、Kubernetes、HealthKit、OCR 或七个完整专业 Agent。
7. 医疗风险升级由确定性规则兜底，模型不能替代医生作诊断或预约。

### 完成定义

以下场景必须在真实进程和真实 PostgreSQL 上通过：

1. 妈妈创建家庭，爸爸通过邀请加入；
2. 创建孕期档案后生成 Today 和未来四周计划；
3. 记录系统超声已预约后，Today 下一优先事项变为材料核对；
4. 任务可以完成、延期、重新分配，并使用版本号防止静默覆盖；
5. 用户告诉 Agent“医生把检查改到下周三”，确认前 PostgreSQL 不变化；
6. 确认后 Eve 通过受控 Tools 调整同一计划，并留下来源和撤销记录；
7. iOS 断开 Eve Stream 后按游标恢复，不重复执行 Tool；
8. Eve 或模型不可用时，Today、计划和家庭功能仍然可用。

### 当前开发环境预检（2026-08-14）

- 已有 Python 3.13.2、Node.js 23.9.0、Swift 6.2.3 Command Line Tools、Docker 29.4 与 Compose 5.1；
- 当前没有 `/Applications/Xcode.app`，`xcodebuild` 不可用；
- Task 1–9 可以先推进；当前已建立 SwiftUI 源码与 Xcode 工程骨架，但完整 Xcode、许可和 iOS Simulator 尚未安装，故 Simulator 编译验收仍是后续门槛；
- Node 23 不是长期基线，Task 2 应依据 Eve 当前支持矩阵选择并锁定 Node LTS。

---

## Task 1：初始化 Monorepo 与统一验证入口

**Files:**

- Create: `.gitignore`
- Create: `.env.example`
- Create: `README.md`
- Create: `Makefile`
- Create: `infrastructure/compose/compose.yaml`
- Create: `scripts/verify_repo.py`
- Create: `tests/test_repo_structure.py`

**Step 1: 写失败的仓库结构测试**

```python
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def test_required_project_roots_exist() -> None:
    required = [
        "apps/ios", "services/api", "services/agent",
        "contracts/public-api", "contracts/agent-tools",
        "content/pregnancy-tasks", "content/safety-rules",
        "content/hangzhou", "infrastructure/compose",
    ]
    missing = [path for path in required if not (ROOT / path).exists()]
    assert missing == []
```

**Step 2: 运行并确认失败**

Run: `python3 -m pytest tests/test_repo_structure.py -q`

Expected: FAIL，缺少核心工程目录。

**Step 3: 创建目录与根级命令**

`Makefile` 只负责编排：

```make
.PHONY: dev test contracts lint verify

dev:
	docker compose -f infrastructure/compose/compose.yaml up --build

test:
	$(MAKE) -C services/api test
	$(MAKE) -C services/agent test

contracts:
	$(MAKE) -C services/api contracts

lint:
	$(MAKE) -C services/api lint
	$(MAKE) -C services/agent lint

verify: lint test contracts
	python3 scripts/verify_repo.py
```

Compose 此时只定义 `postgres`；API 与 Eve 在初始化完成后再加入，避免空容器伪装进度。

**Step 4: 再运行测试**

Run: `python3 -m pytest tests/test_repo_structure.py -q`

Expected: PASS。

**Step 5: 建立版本控制**

若根目录尚未是 Git 仓库：

```bash
git init -b main
git add .
git commit -m "chore: initialize pregnancy app monorepo"
```

---

## Task 2：完成 Eve Runtime 技术验证门

**Files:**

- Create: `services/agent/package.json`
- Create: `services/agent/tsconfig.json`
- Create: `services/agent/agent/agent.ts`
- Create: `services/agent/agent/instructions.md`
- Create: `services/agent/agent/channels/eve.ts`
- Create: `services/agent/agent/tools/echo_context.ts`
- Create: `services/agent/agent/subagents/pregnancy-expert/agent.ts`
- Create: `services/agent/agent/subagents/pregnancy-expert/instructions.md`
- Create: `services/agent/evals/runtime-gate.eval.ts`
- Create: `services/agent/tests/runtime-gate.test.ts`
- Create: `services/agent/Dockerfile`
- Create: `docs/architecture/eve-runtime-validation.md`
- Modify: `docs/architecture/adr/0011-eve-independent-agent-runtime.md`

**Step 1: 固定 Eve 版本而不是长期依赖 `latest`**

先在干净临时目录运行官方脚手架和 `eve info`，记录实际生成结构。Eve 官方仍标为 Preview，生产代码不得根据旧示例猜 API。

```bash
npx eve@latest init /tmp/aim-eve-reference
cd /tmp/aim-eve-reference
npx eve info
```

Expected: 能生成 Agent、编译 `.eve/` 并得到当前版本号。把验证通过的精确版本写入 `services/agent/package.json` 和验证报告。

**Step 2: 先写 Runtime Gate 测试**

必须覆盖：

- `eve build` 成功；
- Shell、文件写入、开放 Web 与通用 built-in `agent` 不暴露；
- Session Auth 能注入 `accountId/familyId/pregnancyId`；
- 根 Agent 可调用只读孕产专家，专家不能调用写 Tool；
- NDJSON Stream 有稳定的 `sessionId`、`continuationToken` 和递增游标；
- 进程重启后恢复同一会话；
- 未授权会话不能调用 Tool；
- `/.well-known/workflow/` 回调路径可用。

**Step 3: 实现最小验证 Agent**

根 Agent 只提供 `echo_context` 和孕产专家，不实现真实产品 Prompt。

```markdown
你是孕期成长规划 Agent 的运行时验证版本。
只验证会话、身份、Subagent、审批和流式恢复。
不得给出医疗诊断，不得执行未声明的工具。
```

**Step 4: 验证自托管进程**

```bash
npm --prefix services/agent run build
PORT=3100 npm --prefix services/agent run start
curl --fail http://127.0.0.1:3100/eve/v1/health
```

Expected: Health 通过，Workflow Store 挂载持久卷；停止并重启进程后会话仍可恢复。

**Step 5: 写 Gate 结论**

`docs/architecture/eve-runtime-validation.md` 必须记录：精确版本、Workflow Store、模型接入、Auth、Tool 权限、Stream 样本、重启恢复、高权限关闭清单和 PASS/HOLD。

若关键项为 HOLD，停止 Agent 功能开发，但可继续 FastAPI 领域实现；不得用模拟结果声称 Eve 已验证。

**Step 6: 提交**

```bash
git add services/agent docs/architecture/eve-runtime-validation.md docs/architecture/adr/0011-eve-independent-agent-runtime.md
git commit -m "spike: validate eve runtime boundaries"
```

---

## Task 3：初始化 FastAPI DDD 骨架与 PostgreSQL

**Files:**

- Create: `services/api/pyproject.toml`
- Create: `services/api/Makefile`
- Create: `services/api/alembic.ini`
- Create: `services/api/migrations/env.py`
- Create: `services/api/src/aim_api/main.py`
- Create: `services/api/src/aim_api/bootstrap.py`
- Create: `services/api/src/aim_api/platform/config/settings.py`
- Create: `services/api/src/aim_api/platform/database/session.py`
- Create: `services/api/src/aim_api/platform/http/errors.py`
- Create: `services/api/src/aim_api/kernel/ids.py`
- Create: `services/api/src/aim_api/kernel/clock.py`
- Create: `services/api/tests/architecture/test_dependencies.py`
- Create: `services/api/tests/integration/test_health.py`

**Step 1: 写架构依赖失败测试**

扫描 `contexts/**/domain`，禁止导入 `fastapi`、`pydantic`、`sqlalchemy` 和其他上下文的 `adapters`。

**Step 2: 写健康检查失败测试**

```python
def test_health_reports_database_ready(client) -> None:
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "database": "ready"}
```

**Step 3: 实现 Bootstrap**

`create_app()` 负责 Router、错误映射、数据库生命周期和 OpenTelemetry 装配；领域代码不能访问全局 Session。

**Step 4: 建立真实 PostgreSQL 测试**

```bash
docker compose -f infrastructure/compose/compose.yaml up -d postgres
make -C services/api test
```

Expected: 架构测试和健康检查通过；测试不能静默退回 SQLite。

**Step 5: 提交**

```bash
git add services/api infrastructure/compose/compose.yaml
git commit -m "feat(api): add ddd service foundation"
```

---

## Task 4：实现 Identity、Family 与邀请闭环

**Files:**

- Create: `services/api/src/aim_api/contexts/identity/domain/account.py`
- Create: `services/api/src/aim_api/contexts/family/domain/family.py`
- Create: `services/api/src/aim_api/contexts/family/domain/invitation.py`
- Create: `services/api/src/aim_api/contexts/family/application/commands/create_family.py`
- Create: `services/api/src/aim_api/contexts/family/application/commands/invite_member.py`
- Create: `services/api/src/aim_api/contexts/family/application/commands/accept_invitation.py`
- Create: `services/api/src/aim_api/contexts/family/application/queries/get_family.py`
- Create: `services/api/src/aim_api/contexts/family/adapters/inbound/http/router.py`
- Create: `services/api/src/aim_api/contexts/family/adapters/outbound/persistence/models.py`
- Create: `services/api/src/aim_api/contexts/family/adapters/outbound/persistence/repositories.py`
- Create: `services/api/tests/domain/family/test_family.py`
- Create: `services/api/tests/integration/family/test_family_api.py`
- Create: `services/api/migrations/versions/0001_identity_family.py`

**Step 1: 写领域测试**

必须覆盖：账号不是妈妈或爸爸；`FamilyMember.role` 才是 `mother/father/other_caregiver`；同一账号不能重复加入家庭；邀请 24 小时过期且只能使用一次；非家庭成员不能读取家庭；邀请成功后成员由 pending 变为 active。

**Step 2: 实现纯领域对象**

领域方法返回 `FamilyMemberInvited` 与 `FamilyMemberJoined`，不发送短信、不访问数据库。

**Step 3: 实现 Application Commands 与 Repository Port**

每个 Command 使用 Unit of Work；手机号发送属于 Adapter，在测试中使用 Fake。

**Step 4: 实现 Public API**

```text
POST /api/v1/families
POST /api/v1/families/{family_id}/invitations
POST /api/v1/family-invitations/{token}/accept
GET  /api/v1/families/{family_id}
```

**Step 5: 真实迁移与 API 测试**

Run: `make -C services/api test`

Expected: Domain、Repository、Migration 与 HTTP 测试全部通过。

---

## Task 5：实现孕期档案、动态孕周和事实来源

**Files:**

- Create: `services/api/src/aim_api/contexts/pregnancy/domain/pregnancy.py`
- Create: `services/api/src/aim_api/contexts/pregnancy/domain/fact.py`
- Create: `services/api/src/aim_api/contexts/pregnancy/domain/gestational_age.py`
- Create: `services/api/src/aim_api/contexts/pregnancy/application/commands/create_pregnancy.py`
- Create: `services/api/src/aim_api/contexts/pregnancy/application/commands/record_fact.py`
- Create: `services/api/src/aim_api/contexts/pregnancy/application/queries/get_pregnancy.py`
- Create: `services/api/src/aim_api/contexts/pregnancy/adapters/inbound/http/router.py`
- Create: `services/api/src/aim_api/contexts/pregnancy/adapters/outbound/persistence/models.py`
- Create: `services/api/tests/domain/pregnancy/test_gestational_age.py`
- Create: `services/api/tests/domain/pregnancy/test_fact_priority.py`
- Create: `services/api/migrations/versions/0002_pregnancy.py`

**Step 1: 写孕周计算测试**

以预产期和查询日期计算 `weeks + days`，不能保存会每日失效的静态孕周。

**Step 2: 写事实优先级测试**

事实优先级为：医生确认 > 用户确认 > 机器提取 > Agent 推导 > 普通知识。低优先级事实不得静默覆盖高优先级事实；冲突产生 `needs_verification`。

**Step 3: 实现档案与 API**

```text
POST /api/v1/families/{family_id}/pregnancies
GET  /api/v1/pregnancies/{pregnancy_id}
POST /api/v1/pregnancies/{pregnancy_id}/facts
```

**Step 4: 测试家庭隔离**

使用另一个家庭的 Token 读写孕期档案必须返回 403。

---

## Task 6：实现 Planning 核心聚合与变更历史

**Files:**

- Create: `services/api/src/aim_api/contexts/planning/domain/plan.py`
- Create: `services/api/src/aim_api/contexts/planning/domain/task.py`
- Create: `services/api/src/aim_api/contexts/planning/domain/task_status.py`
- Create: `services/api/src/aim_api/contexts/planning/domain/task_change.py`
- Create: `services/api/src/aim_api/contexts/planning/application/commands/generate_initial_plan.py`
- Create: `services/api/src/aim_api/contexts/planning/application/commands/schedule_task.py`
- Create: `services/api/src/aim_api/contexts/planning/application/commands/complete_task.py`
- Create: `services/api/src/aim_api/contexts/planning/application/commands/delay_task.py`
- Create: `services/api/src/aim_api/contexts/planning/application/commands/assign_task.py`
- Create: `services/api/src/aim_api/contexts/planning/application/commands/undo_change.py`
- Create: `services/api/src/aim_api/contexts/planning/application/queries/get_plan.py`
- Create: `services/api/src/aim_api/contexts/planning/adapters/inbound/http/router.py`
- Create: `services/api/tests/domain/planning/test_task_lifecycle.py`
- Create: `services/api/tests/application/planning/test_commands.py`
- Create: `services/api/tests/integration/planning/test_optimistic_lock.py`
- Create: `services/api/migrations/versions/0003_planning.py`

**Step 1: 写状态机测试**

允许 `todo -> scheduled -> done`、`todo -> done` 和 `done -> todo`。禁止重复完成、无效负责人、无孕期计划归属和非法版本覆盖。

**Step 2: 实现来源与版本**

每个 Task 保存 `source_type/source_id/changed_by_actor_type/changed_by_actor_id/version/scheduled_for/due_at/assigned_member_id`。

**Step 3: 实现用户操作 API**

```text
GET   /api/v1/pregnancies/{pregnancy_id}/plan
POST  /api/v1/tasks/{task_id}/schedule
POST  /api/v1/tasks/{task_id}/complete
POST  /api/v1/tasks/{task_id}/delay
POST  /api/v1/tasks/{task_id}/assign
POST  /api/v1/task-changes/{change_id}/undo
```

所有修改携带 `expected_version`；冲突返回 `409 task.version_conflict`。

**Step 4: 对齐原型场景**

系统超声由 `todo` 变为 `scheduled` 后，材料核对成为 Today 第一优先，不删除或复制原任务。

---

## Task 7：实现 Guidance 内容与 Today Composition

**Files:**

- Create: `content/pregnancy-tasks/schema.json`
- Create: `content/pregnancy-tasks/week-18.yaml`
- Create: `content/safety-rules/schema.json`
- Create: `content/safety-rules/pregnancy-red-flags.yaml`
- Create: `content/hangzhou/schema.json`
- Create: `content/hangzhou/pregnancy-benefits.yaml`
- Create: `services/api/src/aim_api/contexts/guidance/domain/guidance_item.py`
- Create: `services/api/src/aim_api/contexts/guidance/application/queries/get_guidance.py`
- Create: `services/api/src/aim_api/composition/today/query.py`
- Create: `services/api/src/aim_api/composition/today/router.py`
- Create: `services/api/tests/contract/content/test_content_schema.py`
- Create: `services/api/tests/integration/composition/test_today.py`

**Step 1: 为内容写 Schema 测试**

每条内容必须包含 `id/version/source/source_url/reviewed_at/applicability`。杭州政策不得只写结论而没有适用范围和核验日期。

**Step 2: 实现初始计划生成**

以孕周 18+3 和杭州为测试输入，生成与原型相同的核心任务，但 ID、日期和负责人来自领域规则，而不是写死在 Router。

**Step 3: 实现 Today Read Model**

`GET /api/v1/pregnancies/{pregnancy_id}/today` 返回孕周、第一优先任务、接下来任务、Agent 最近状态和家庭任务计数。Composition 只读，不绕过 Planning 写入。

---

## Task 8：实现 Agent Access、受控 Tools 与契约生成

**Files:**

- Create: `services/api/src/aim_api/contexts/agent_access/domain/tool_invocation.py`
- Create: `services/api/src/aim_api/contexts/agent_access/application/authorize_tool.py`
- Create: `services/api/src/aim_api/contexts/agent_access/application/execute_tool.py`
- Create: `services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/router.py`
- Create: `services/api/tests/integration/agent_access/test_tool_auth.py`
- Create: `services/api/tests/integration/agent_access/test_idempotency.py`
- Create: `services/api/tests/contract/test_openapi_snapshots.py`
- Create: `contracts/public-api/openapi.json`
- Create: `contracts/agent-tools/openapi.json`

**Step 1: 写权限和幂等失败测试**

必须验证：模型传入的 `family_id` 被忽略；身份只来自 Eve Session 与签名 Header；Service Credential 不能替代家庭成员权限；`sessionId + callId` 重复调用返回同一个 `operation_id`；不同请求复用幂等键返回 409；写 Tool 未批准返回 `approval_required`。

**Step 2: 实现 Internal Tool API**

```text
POST /internal/agent-tools/get-pregnancy-context
POST /internal/agent-tools/list-tasks
POST /internal/agent-tools/update-task
POST /internal/agent-tools/assign-task
POST /internal/agent-tools/record-pregnancy-fact
POST /internal/agent-tools/get-guidance
POST /internal/agent-tools/undo-operation
```

统一结果：

```json
{
  "operation_id": "op_...",
  "status": "completed",
  "summary": "检查日期已调整到 8月19日",
  "data": {"task_id": "task_...", "version": 3}
}
```

**Step 3: 分离两份 OpenAPI**

Public API 不暴露 Internal Tool；Internal Tool 契约不包含登录或管理 API。

Run: `make contracts`

Expected: 两份快照生成稳定，Swift 与 TypeScript Client 都能编译。

---

## Task 9：实现成长规划 Agent、孕产专家、Skills 与确认流

**Files:**

- Modify: `services/agent/agent/instructions.md`
- Create: `services/agent/agent/tools/get_pregnancy_context.ts`
- Create: `services/agent/agent/tools/list_tasks.ts`
- Create: `services/agent/agent/tools/update_task.ts`
- Create: `services/agent/agent/tools/assign_task.ts`
- Create: `services/agent/agent/tools/get_guidance.ts`
- Create: `services/agent/agent/lib/business-api/client.ts`
- Create: `services/agent/agent/lib/auth/session-context.ts`
- Create: `services/agent/agent/skills/adjust-pregnancy-plan/SKILL.md`
- Modify: `services/agent/agent/subagents/pregnancy-expert/instructions.md`
- Create: `services/agent/evals/plan-change.eval.ts`
- Create: `services/agent/tests/tools/idempotency.test.ts`
- Create: `services/agent/tests/plan-change-flow.test.ts`

**Step 1: 写确定性 Eval**

输入 `医生把检查改到下周三了`。确认前只允许产生理解和变更预览：检查日期为 `2026-08-19` 且具体时间为 `null`、材料提前到 `2026-08-18`、资料整理继续由爸爸负责；数据库写 Tool 调用次数必须为 0。

**Step 2: 实现只读专家边界**

孕产专家只返回结构化判断和风险级别，不拥有 `update_task`、`assign_task` 或通用代理工具。

**Step 3: 实现确认后的 Tool 调用**

三项变化使用稳定 `callId`，每项 Tool Result 写入会话事件。部分失败时显示实际完成项与安全重试入口，不能声称“全部完成”。

**Step 4: 实现撤销**

撤销调用 FastAPI `undo-operation`，不让 Agent 根据旧文本反向猜修改。

**Step 5: 运行 Evals 与集成测试**

```bash
npm --prefix services/agent test
npm --prefix services/agent run eval
```

Expected: 确认前零写入、确认后恰好三项操作、重试零重复、危险输入进入风险升级。

---

## Task 10：初始化 SwiftUI App 与客户端边界

**Files:**

- Create: `apps/ios/AimApp.xcodeproj`
- Create: `apps/ios/AimApp/App/AimApp.swift`
- Create: `apps/ios/AimApp/App/AppSessionStore.swift`
- Create: `apps/ios/AimApp/Core/Networking/APIEnvironment.swift`
- Create: `apps/ios/AimApp/Core/Persistence/ModelContainer.swift`
- Create: `apps/ios/AimApp/Core/DesignSystem/AimTheme.swift`
- Create: `apps/ios/AimApp/Clients/BusinessAPIClient/BusinessRepository.swift`
- Create: `apps/ios/AimApp/Clients/EveClient/EveClient.swift`
- Create: `apps/ios/AimApp/Clients/EveClient/EveEvent.swift`
- Create: `apps/ios/AimApp/Generated/OpenAPI/`
- Create: `apps/ios/AimApp/Tests/EveClientTests.swift`
- Create: `apps/ios/AimApp/Tests/BusinessRepositoryTests.swift`

**Step 1: 生成而非手写 Public API Client**

从 `contracts/public-api/openapi.json` 生成 Swift 类型；Generated DTO 由 Repository 转换，不能直接作为 SwiftUI View State。

**Step 2: 先写 Eve NDJSON Decoder 测试**

覆盖分片行、空行、未知事件、游标递增、断线恢复和重复事件去重。

**Step 3: 实现 `actor EveClient`**

```swift
actor EveClient {
    func start(message: String) async throws -> AsyncThrowingStream<EveEvent, Error>
    func resume(sessionID: String, from index: Int) async throws -> AsyncThrowingStream<EveEvent, Error>
    func respondToApproval(sessionID: String, approvalID: String, approved: Bool) async throws
    func cancel(sessionID: String) async throws
}
```

精确 HTTP 路径和事件字段必须来自 Task 2 验证报告，不得从原型推测。

**Step 4: 实现本地数据边界**

SwiftData 只缓存 Today/Plan Read Model、Eve Cursor 和普通 Task Operation；Token 存 Keychain。

---

## Task 11：实现 iOS Onboarding、Today、Plan 与 Family

**Files:**

- Create: `apps/ios/AimApp/Features/Onboarding/OnboardingView.swift`
- Create: `apps/ios/AimApp/Features/Onboarding/OnboardingStore.swift`
- Create: `apps/ios/AimApp/Features/Today/TodayView.swift`
- Create: `apps/ios/AimApp/Features/Today/TodayStore.swift`
- Create: `apps/ios/AimApp/Features/Plan/PlanView.swift`
- Create: `apps/ios/AimApp/Features/Plan/PlanStore.swift`
- Create: `apps/ios/AimApp/Features/Family/FamilyView.swift`
- Create: `apps/ios/AimApp/Features/Family/FamilyStore.swift`
- Create: `apps/ios/AimApp/Features/TaskDetail/TaskDetailView.swift`
- Create: `apps/ios/AimApp/Features/TaskDetail/TaskDetailStore.swift`
- Create: `apps/ios/AimApp/Tests/TodayStoreTests.swift`
- Create: `apps/ios/AimApp/Tests/TaskDetailStoreTests.swift`
- Create: `apps/ios/AimApp/UITests/CoreJourneyUITests.swift`

**Step 1: 先写 Store 测试**

覆盖加载、重试、安排任务、完成、延期、改负责人、409 刷新与撤销。

**Step 2: 按原型实现原生视图**

以 `prototype/audit/interaction-v2/` 为流程参照，使用系统大标题、List/Form/Sheet、SF Symbols、Dynamic Type 和 VoiceOver；不要把 Web 原型逐像素翻译成自绘组件。

**Step 3: 验证共享事实**

Today、Plan 与 Family 不维护三份独立任务状态；写操作完成后统一从 BusinessRepository 刷新服务端事实。

**Step 4: 验证离线降级**

无网时可读取缓存 Today/Plan，普通任务操作进入队列；邀请和 Agent 明确提示需要网络。

---

## Task 12：实现 iOS 全局 Agent Sheet 与计划确认

**Files:**

- Create: `apps/ios/AimApp/Features/Agent/AgentSheet.swift`
- Create: `apps/ios/AimApp/Features/Agent/AgentStore.swift`
- Create: `apps/ios/AimApp/Features/Agent/AgentModels.swift`
- Create: `apps/ios/AimApp/Features/Agent/PlanChangeReviewView.swift`
- Create: `apps/ios/AimApp/Tests/AgentStoreTests.swift`
- Create: `apps/ios/AimApp/UITests/AgentPlanChangeUITests.swift`

**Step 1: 写状态机测试**

```text
idle -> streamingUnderstanding -> awaitingConfirmation
awaitingConfirmation -> applying -> applied
awaitingConfirmation -> cancelled
applying -> partialFailure / failed
applied -> undoing -> undone
```

**Step 2: 实现全局 Sheet**

文本输入只存在于 Sheet；关闭、提交和 Tab 切换必须释放键盘焦点。Agent Tab 展示活动与历史，不放常驻输入框。

**Step 3: 实现确认边界**

变更预览展示理解、受影响任务、执行边界和是否需要医疗/用户决定。用户确认前不刷新出虚假的业务变化。

**Step 4: Tool 完成后重新拉取业务事实**

Agent Stream 只驱动过程 UI；`applied` 的最终 Today/Plan 来自 FastAPI 查询。

---

## Task 13：端到端、故障与安全验收

**Files:**

- Create: `tests/e2e/test_core_journey.py`
- Create: `tests/e2e/test_agent_confirmation.py`
- Create: `tests/e2e/test_eve_resume.py`
- Create: `tests/e2e/test_family_isolation.py`
- Create: `tests/e2e/test_degraded_mode.py`
- Create: `docs/testing/core-journey-acceptance.md`
- Create: `docs/operations/local-development.md`
- Create: `docs/operations/backup-restore.md`

**Step 1: 启动真实栈**

Run: `make dev`

Expected: PostgreSQL、FastAPI、Eve 健康；iOS Simulator 可连接统一入口。

**Step 2: 运行核心旅程**

Run: `python3 -m pytest tests/e2e -q`

不得 Mock PostgreSQL、FastAPI 或 Eve；模型可用确定性 Mock Model，但 Tool、Stream 和 Workflow Store 必须真实。

**Step 3: 运行故障注入**

- 确认前终止 Eve：零业务写入；
- Tool 成功后断线：恢复时不重复；
- Eve 整体停机：普通业务继续；
- 两个家庭并发访问：严格隔离；
- 两位成员并发改同一任务：一方得到 409；
- PostgreSQL 写失败：Agent 不显示成功；
- 触发安全红旗：停止普通建议并明确升级。

**Step 4: 完整验证**

Run: `make verify`

Expected: Python、TypeScript、Swift、契约、迁移、Evals、E2E 全通过。

---

## 实施阶段与 Gate

| 阶段 | Tasks | Gate |
|---|---:|---|
| A. 工程与 Runtime 验证 | 1–2 | Eve 自托管、Auth、Stream、Subagent、Tool 限权均有证据 |
| B. 业务事实中心 | 3–7 | 家庭、孕期、任务、Today 在无 Agent 时独立可用 |
| C. Agent Tool 闭环 | 8–9 | 确认前零写入，确认后幂等、可追踪、可撤销 |
| D. iOS 产品闭环 | 10–12 | 原型主链在 SwiftUI 与真实 API 上完成 |
| E. 正式验收 | 13 | `make verify` 与真实恢复、隔离测试通过 |

## Coding Agent 执行规则

1. 一次只执行一个 Task；每个 Task 先补失败测试，再实现，再验证。
2. 不因目录图存在就提前创建空模块。
3. 修改架构边界前先新增或修订 ADR；不得只改代码。
4. Eve 文档与计划不一致时，以当前安装包 `node_modules/eve/docs/` 和官方 Changelog 为准，并把差异写入验证报告。
5. 所有医疗示例只用于流程验证，不作为真实医疗建议或事实库内容。
6. 未跑真实命令、未看到通过证据，不得把 Task 标为完成。

## 推荐第一轮执行范围

第一轮只执行 Task 1–2。原因不是缩小产品，而是 Eve 是当前唯一高不确定技术依赖；先证明 Runtime 边界，随后 FastAPI、iOS 和 Agent 实施可以按稳定契约连续推进。

Task 2 Gate 通过后，按 Task 3–13 顺序持续实施，不重新讨论已接受的 DDD、FastAPI、PostgreSQL、SwiftUI 和家庭模型决策。
