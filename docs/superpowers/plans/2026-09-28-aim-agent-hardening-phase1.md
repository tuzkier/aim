# AIM Agent 补全 · 第一期「链路修通」实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 AIM 已有的功能端到端真正可用：撤销一定能用、确认卡显示真实内容、快捷入口带上下文、AIM 写入后 App 自动刷新、线上不会静默退回假模型。

**Architecture:** 服务端把撤销统一到「操作编号」（`tool_invocations.operation_id`），并在调用记录里存下账号与孕期作用域；Eve 侧按确认档位拆分工具；网页端按消息挂确认按钮、按工具渲染确认卡、用 Eve 的 `clientContext` 带页面上下文、从事件流判断写入并通知原生；iOS 注入入口模式与 ID、处理跳转、按通知刷新各 store。

**Tech Stack:** FastAPI + SQLAlchemy + Alembic（`services/api`）；Eve 0.47.2 + zod（`services/agent`）；React 19 + assistant-ui 0.15 + `@assistant-ui/eve` + Vite + Vitest（`apps/agent-web`）；SwiftUI + WKWebView（`apps/ios`）。

**Spec:** `docs/superpowers/specs/2026-09-28-aim-agent-hardening-design.md` §2、§3。

## Global Constraints

- 用户可见文案一律简体中文。
- 写操作分档（服务端 `DIRECT_EXECUTION_TOOLS` 为唯一权威，Eve 侧 `approval: always()` 与之一致）：
  - 直接执行：`create_task`、`create_record`、`complete_task`、`undo_operation`
  - 执行前确认：`reschedule_task`、`assign_task`、`record_pregnancy_fact`、`create_knowledge`
- 卡片上的待办标题、成员称呼、孕期信息旧值由网页凭 ID 调公开 API 查出，**不采信模型参数里的展示性描述**。
- `record_pregnancy_fact` 本期不支持撤销，返回「孕期信息不能撤销，直接告诉我正确的值即可」。
- 网页端 `eve` 与运行时一致为 `0.47.2`。
- **iOS 不新增 Swift 文件**：`project.pbxproj` 是手工登记的，新类型放进既有文件，新测试放进既有测试文件。
- 生产开关用 `AIM_DEPLOYMENT=production`，不要用 `NODE_ENV`（Dockerfile 对本地栈也设了 `production`）。
- 提交信息沿用仓库风格：`feat(api): …`、`fix(web): …`，中文描述。

## 运行测试的前置条件

- API 集成测试需要本地 Postgres：先 `make dev`（Compose 栈，Postgres 在 `127.0.0.1:55434`）。
  运行：`cd services/api && PYTHONPATH=src python -m pytest <path> -v`
- Agent 测试：`cd services/agent && npm run build && npm test`（`runtime-gate.test.ts` 读 `.eve/` 编译产物，必须先 build）。
- 网页测试：`cd apps/agent-web && npm test`（Task 1 引入 Vitest）。
- iOS 测试：`make ios-test`。已知 UI 测试有两条既有失败，与本计划无关，不要去修。

## 文件结构

**services/api**
- `migrations/versions/0009_tool_invocation_scope.py`（新建）——`tool_invocations` 加 `account_id` / `family_id` / `pregnancy_id` / `undone_at`
- `src/aim_api/contexts/agent_access/domain/tool_invocation.py`——领域对象加作用域与撤销标记
- `src/aim_api/contexts/agent_access/adapters/outbound/persistence/models.py`、`repositories.py`——持久化新列，按操作编号读取，标记已撤销
- `src/aim_api/contexts/planning/application/ports.py`、`adapters/outbound/persistence/repositories.py`——按「变更后版本」取 task change
- `src/aim_api/contexts/agent_access/adapters/inbound/http/router.py`——`complete-task` / `reschedule-task` 端点，`undo-operation` 改收 `operation_id`，孕期上下文带成员；删除 `update-task` / `delete-task` / `delete-record`
- `src/aim_api/contexts/agent_access/adapters/inbound/http/operation_undo.py`（新建）——撤销的反向逻辑 + 公开端点 `POST /api/v1/agent/operations/{operation_id}/undo`
- `src/aim_api/bootstrap.py`——注册公开撤销路由
- `contracts/public-api/openapi.json`——重新生成
- 测试：`tests/integration/agent_access/test_operation_undo.py`（新建）、`test_authoring_tools.py`、`test_idempotency.py`、`test_tool_invocation_scope.py`（新建）、`test_pregnancy_context_tool.py`（新建）

**services/agent**
- `agent/tools/complete_task.ts`、`agent/tools/reschedule_task.ts`（新建）
- `agent/tools/undo_operation.ts`、`agent/tools/create_record.ts`、`agent/tools/assign_task.ts`（改）
- 删除：`agent/tools/update_task.ts`、`delete_task.ts`、`delete_record.ts`、`preview_task_change.ts`
- `agent/lib/auth/session-context.ts`——无孕期档案的中文错误
- `agent/lib/model-config.ts`、`agent/agent.ts`——生产禁止 mock
- `agent/instructions.md`、`agent/skills/adjust-pregnancy-plan/SKILL.md`
- `infrastructure/compose/compose.prod.yaml`
- 测试：`tests/tools/authoring.test.ts`、`tests/plan-change-flow.test.ts`、`tests/runtime-gate.test.ts`、`tests/model-config.test.ts`、`tests/auth.test.ts`

**apps/agent-web**
- `package.json`——依赖对齐、加 Vitest
- `src/bridge.ts`——`NativeContext` 加 `familyId` / `pregnancyId` / `entry`；`notifyTurnFinished(kinds)`
- `src/entry.ts`（新建）——入口模式解析
- `src/turnWrites.ts`（新建）——从事件流收集本轮写入类别
- `src/approvals.tsx`、`src/approvalBatch.ts`（新建，纯函数）——攒批与失败重试
- `src/bizData.tsx`（新建）——向公开 API 取待办、成员、孕期信息
- `src/tools/labels.ts`、`types.ts`、`ToolGroup.tsx`、`ToolCard.tsx`、`CreateTask.tsx`、`CreateKnowledge.tsx`、`index.tsx`
- `src/tools/RescheduleTask.tsx`、`AssignTask.tsx`、`RecordFact.tsx`、`CompleteTask.tsx`、`CreateRecord.tsx`（新建）
- `src/thread/ContextChip.tsx`（新建）
- `src/App.tsx`
- `src/styles.css`
- 测试：`src/*.test.ts`

**apps/ios**
- `AimApp/Features/Agent/AgentWebView.swift`——`AgentWebEntry`、JSON 载荷、`aimTurnFinished` 带类别
- `AimApp/Features/Agent/AgentView.swift`——入口、跳转、标签页出现时同步、`AgentDestinations`
- `AimApp/Features/Agent/AgentStore.swift`——`pendingAutoSend`、`prepareAnalysis`
- `AimApp/App/AimApp.swift`——注入 `AgentDestinations`，按通知刷新
- `AimApp/Features/Home/HomeView.swift`、`AimApp/Features/Records/RecordDetailView.swift`
- 测试：`AimApp/Tests/AgentStoreTests.swift`

---

### Task 1：网页端依赖对齐，引入 Vitest

**Files:**
- Modify: `apps/agent-web/package.json`
- Create: `apps/agent-web/vitest.config.ts`
- Create: `apps/agent-web/src/smoke.test.ts`（本任务结束时删除）

**Interfaces:**
- Produces: `npm test` 可运行 Vitest（node 环境）；`eve@0.47.2`、`@assistant-ui/eve@0.0.19`。

- [ ] **Step 1: 升级依赖并加 Vitest**

```bash
cd apps/agent-web
npm install --save-exact eve@0.47.2 @assistant-ui/eve@0.0.19
npm install --save-dev vitest
```

- [ ] **Step 2: 加测试脚本与配置**

`package.json` 的 `scripts` 加一行：

```json
"test": "vitest run"
```

`apps/agent-web/vitest.config.ts`：

```ts
import { defineConfig } from "vitest/config";

// 只测纯逻辑（入口解析、攒批、事件归纳、文案）。组件测试放到第三期。
export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
  },
});
```

- [ ] **Step 3: 写一个冒烟测试确认 Vitest 跑得起来**

`apps/agent-web/src/smoke.test.ts`：

```ts
import { expect, test } from "vitest";

test("vitest runs", () => {
  expect(1 + 1).toBe(2);
});
```

Run: `cd apps/agent-web && npm test`
Expected: 1 passed

- [ ] **Step 4: 类型检查与构建**

Run: `cd apps/agent-web && npx tsc --noEmit && npm run build`
Expected: 无错误。若 `@assistant-ui/eve` 0.0.19 改了导出名（`useEveAgentRuntime`、`useEveEvents`、`useEveSession`、`useEveError`、`useEveReset`），按编译错误对照 `node_modules/@assistant-ui/eve/dist/index.d.ts` 改 `src/App.tsx` 的 import；不要改动行为。

- [ ] **Step 5: 本地栈回归一遍现有流程**

`make dev` 起栈，`cd apps/agent-web && npm run dev`（`.env.local` 配 `VITE_AIM_DEV_PHONE` / `VITE_AIM_DEV_PASSWORD`），浏览器打开 Vite 地址：
1. 发一句「你好」，助手文字边流边显；
2. 说「帮我把番茄炒蛋和清蒸鲈鱼收进菜谱」，两张卡出现，点一次确认，两张都变成已收录；
3. 刷新页面，上一段对话接回来。

Expected: 三步均正常。任何一步失败先修到正常再往下走——后续任务都以这个版本为基线。

- [ ] **Step 6: 删掉冒烟测试并提交**

```bash
rm apps/agent-web/src/smoke.test.ts
git add apps/agent-web/package.json apps/agent-web/package-lock.json apps/agent-web/vitest.config.ts apps/agent-web/src
git commit -m "chore(web): eve 升到 0.47.2 与运行时一致，引入 Vitest"
```

---

### Task 2：工具调用记录作用域与撤销标记

**Files:**
- Create: `services/api/migrations/versions/0009_tool_invocation_scope.py`
- Modify: `services/api/src/aim_api/contexts/agent_access/domain/tool_invocation.py`
- Modify: `services/api/src/aim_api/contexts/agent_access/adapters/outbound/persistence/models.py`
- Modify: `services/api/src/aim_api/contexts/agent_access/adapters/outbound/persistence/repositories.py`
- Modify: `services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/router.py`（`_run` 里的 `ToolInvocation.start`）
- Test: `services/api/tests/integration/agent_access/test_tool_invocation_scope.py`

**Interfaces:**
- Produces:
  - `ToolInvocation` 新字段 `account_id: UUID | None`、`family_id: UUID | None`、`pregnancy_id: UUID | None`、`undone_at: datetime | None`
  - `ToolInvocation.start(*, session_id, call_id, tool_name, request_hash, account_id=None, family_id=None, pregnancy_id=None)`
  - `SqlAlchemyToolInvocationRepository.get_by_operation(operation_id: UUID) -> ToolInvocation | None`
  - `SqlAlchemyToolInvocationRepository.mark_undone(operation_id: UUID, at: datetime) -> None`

- [ ] **Step 1: 写失败测试**

`services/api/tests/integration/agent_access/test_tool_invocation_scope.py`：

```python
from __future__ import annotations

import os
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings

GATEWAY = "/internal/agent-tools"


def _sync_url() -> str:
    return os.environ["DATABASE_URL"].replace("+asyncpg", "+psycopg", 1)


def _phone(account_id: str) -> str:
    return "138" + str(int(UUID(account_id)) % 10**8).zfill(8)


def test_invocation_remembers_who_it_acted_for() -> None:
    """撤销要校验「这次操作是不是你的」，调用记录里就得有账号与孕期。"""
    account_id = str(uuid4())
    phone = _phone(account_id)
    token = issue_session_token(UUID(account_id), phone, get_settings().auth_secret)
    public = {"Authorization": f"Bearer {token}"}
    with TestClient(create_app()) as client:
        family = client.post(
            "/api/v1/families", headers=public, json={"name": "作用域家庭", "role": "mother"}
        ).json()
        pregnancy = client.post(
            f"/api/v1/families/{family['id']}/pregnancies",
            headers=public,
            json={"due_date": "2027-01-12"},
        ).json()
        client.post(
            f"/api/v1/pregnancies/{pregnancy['id']}/plan",
            headers=public,
            json={"as_of": "2026-08-14"},
        )
        response = client.post(
            f"{GATEWAY}/create-task",
            headers={
                "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
                "Actor-Account-Id": account_id,
                "Family-Id": family["id"],
                "Pregnancy-Id": pregnancy["id"],
                "Eve-Session-Id": f"eve-scope-{account_id}",
                "Idempotency-Key": "scope-1",
            },
            json={"title": "记下作用域"},
        )
        assert response.status_code == 200, response.text
        operation_id = response.json()["operation_id"]

    engine = create_engine(_sync_url())
    with engine.connect() as conn:
        row = conn.execute(
            text(
                "SELECT account_id, family_id, pregnancy_id, undone_at "
                "FROM tool_invocations WHERE operation_id = :id"
            ),
            {"id": operation_id},
        ).one()
    engine.dispose()
    assert str(row.account_id) == account_id
    assert str(row.family_id) == family["id"]
    assert str(row.pregnancy_id) == pregnancy["id"]
    assert row.undone_at is None
```

- [ ] **Step 2: 运行确认失败**

Run: `cd services/api && PYTHONPATH=src python -m pytest tests/integration/agent_access/test_tool_invocation_scope.py -v`
Expected: FAIL，`column "account_id" does not exist`

- [ ] **Step 3: 迁移**

`services/api/migrations/versions/0009_tool_invocation_scope.py`：

```python
"""Record whom an agent tool call acted for, and whether it has been undone."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0009_tool_invocation_scope"
down_revision = "0008_account_deletion"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 历史行这几列为空：它们没法经公开接口撤销，这是可以接受的——
    # 撤销针对的是刚刚发生的事，不是几周前的调用。
    op.add_column("tool_invocations", sa.Column("account_id", sa.Uuid(), nullable=True))
    op.add_column("tool_invocations", sa.Column("family_id", sa.Uuid(), nullable=True))
    op.add_column("tool_invocations", sa.Column("pregnancy_id", sa.Uuid(), nullable=True))
    op.add_column(
        "tool_invocations",
        sa.Column("undone_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_tool_invocations_account", "tool_invocations", ["account_id"])


def downgrade() -> None:
    op.drop_index("ix_tool_invocations_account", table_name="tool_invocations")
    op.drop_column("tool_invocations", "undone_at")
    op.drop_column("tool_invocations", "pregnancy_id")
    op.drop_column("tool_invocations", "family_id")
    op.drop_column("tool_invocations", "account_id")
```

- [ ] **Step 4: 模型、领域、仓储**

`models.py` 的 `ToolInvocationModel` 在 `created_at` 之后加：

```python
    #: 这次调用代表谁、作用在哪段孕期。撤销时据此校验归属。
    account_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
    family_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
    pregnancy_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
    #: 已被撤销的时刻。再次撤销时直接返回成功。
    undone_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
```

`domain/tool_invocation.py` 的 `ToolInvocation` 在 `created_at` 之后加字段，并扩展 `start`：

```python
    account_id: UUID | None = None
    family_id: UUID | None = None
    pregnancy_id: UUID | None = None
    undone_at: datetime | None = None

    @classmethod
    def start(
        cls,
        *,
        session_id: str,
        call_id: str,
        tool_name: str,
        request_hash: str,
        account_id: UUID | None = None,
        family_id: UUID | None = None,
        pregnancy_id: UUID | None = None,
    ) -> ToolInvocation:
        return cls(
            operation_id=uuid4(),
            session_id=session_id,
            call_id=call_id,
            tool_name=tool_name,
            request_hash=request_hash,
            status=ToolInvocationStatus.completed,
            result={},
            created_at=datetime.now(UTC),
            account_id=account_id,
            family_id=family_id,
            pregnancy_id=pregnancy_id,
        )
```

（`ToolInvocation` 若是 `slots=True` 的 dataclass，带默认值的新字段放在所有无默认值字段之后即可。）

`repositories.py`：`add` 里给 `ToolInvocationModel(...)` 补 `account_id=invocation.account_id, family_id=invocation.family_id, pregnancy_id=invocation.pregnancy_id, undone_at=invocation.undone_at`；`_to_domain` 补同名四个字段；新增两个方法：

```python
    async def get_by_operation(self, operation_id: UUID) -> ToolInvocation | None:
        model = await self.session.get(ToolInvocationModel, operation_id)
        return _to_domain(model) if model else None

    async def mark_undone(self, operation_id: UUID, at: datetime) -> None:
        await self.session.execute(
            update(ToolInvocationModel)
            .where(ToolInvocationModel.operation_id == operation_id)
            .values(undone_at=at)
        )
```

文件头 import 补 `from datetime import datetime`、`from uuid import UUID`、`from sqlalchemy import select, update`。

- [ ] **Step 5: `_run` 写入作用域**

`router.py` 的 `_run` 里：

```python
        invocation = ToolInvocation.start(
            session_id=context.session_id,
            call_id=context.call_id,
            tool_name=tool_name,
            request_hash=request_hash,
            account_id=context.account_id,
            family_id=context.family_id,
            pregnancy_id=context.pregnancy_id,
        )
```

- [ ] **Step 6: 运行确认通过，并跑 agent_access 全部测试**

Run: `cd services/api && PYTHONPATH=src python -m pytest tests/integration/agent_access -v`
Expected: 全部 PASS

- [ ] **Step 7: 提交**

```bash
git add services/api/migrations/versions/0009_tool_invocation_scope.py services/api/src/aim_api/contexts/agent_access services/api/tests/integration/agent_access/test_tool_invocation_scope.py
git commit -m "feat(api): 工具调用记录代表的账号与孕期，并可标记已撤销"
```

---

### Task 3：拆分「完成待办」与「改期待办」，写入结果带 change_id

**Files:**
- Modify: `services/api/src/aim_api/contexts/planning/application/ports.py`
- Modify: `services/api/src/aim_api/contexts/planning/adapters/outbound/persistence/repositories.py`
- Modify: `services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/router.py`
- Modify: `services/api/tests/integration/agent_access/test_authoring_tools.py`
- Modify: `services/api/tests/integration/agent_access/test_idempotency.py`

**Interfaces:**
- Consumes: Task 2 的 `_run`。
- Produces:
  - `PlanningRepositoryPort.get_change_by_version(task_id: UUID, version_after: int) -> TaskChange | None`
  - 内部端点 `POST /internal/agent-tools/complete-task`，body `{task_id, expected_version}`，直接执行；`data = {task_id, title, version, status, change_id}`
  - 内部端点 `POST /internal/agent-tools/reschedule-task`，body `{task_id, expected_version, kind: "schedule"|"delay", at: datetime, approved}`，需确认；`data` 同上
  - `assign-task` 的 `data` 增加 `title`、`change_id`
  - `DIRECT_EXECUTION_TOOLS = {"create_task", "create_record", "complete_task", "undo_operation"}`
  - 删除 `/update-task`

- [ ] **Step 1: 写失败测试**

在 `test_authoring_tools.py` 末尾，把 `TestPermissionTiersStayDistinct` 整个替换为：

```python
class TestPermissionTiersStayDistinct:
    """完成待办挪到「直接执行」，改期仍要确认。"""

    def test_complete_task_executes_directly_and_returns_change_id(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)
            task_id = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t1"),
                json={"title": "产检"},
            ).json()["data"]["task_id"]

            response = client.post(
                f"{GATEWAY}/complete-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t2"),
                json={"task_id": task_id, "expected_version": 1},
            )
            assert response.status_code == 200, response.text
            data = response.json()["data"]
            assert data["status"] == "done"
            assert data["title"] == "产检"
            assert UUID(data["change_id"])

    def test_reschedule_task_still_requires_approval(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)
            task_id = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t3"),
                json={"title": "先建一条"},
            ).json()["data"]["task_id"]

            response = client.post(
                f"{GATEWAY}/reschedule-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t4"),
                json={
                    "task_id": task_id,
                    "expected_version": 1,
                    "kind": "delay",
                    "at": "2026-10-09T09:00:00Z",
                },
            )
            assert response.status_code == 409, response.text
            assert response.json()["error"]["code"] == "approval_required"

    def test_approved_reschedule_returns_change_id(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)
            task_id = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t5"),
                json={"title": "改期对象"},
            ).json()["data"]["task_id"]

            response = client.post(
                f"{GATEWAY}/reschedule-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t6"),
                json={
                    "task_id": task_id,
                    "expected_version": 1,
                    "kind": "schedule",
                    "at": "2026-10-09T09:00:00Z",
                    "approved": True,
                },
            )
            assert response.status_code == 200, response.text
            assert UUID(response.json()["data"]["change_id"])
            assert response.json()["data"]["status"] == "scheduled"

    def test_update_task_endpoint_is_gone(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)
            response = client.post(
                f"{GATEWAY}/update-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t7"),
                json={},
            )
            assert response.status_code == 404
```

`test_idempotency.py` 里把 `update-task` 的三处调用改成 `reschedule-task`，body 改为：

```python
        body = {
            "task_id": ultrasound_id,
            "expected_version": 1,
            "kind": "schedule",
            "at": "2026-08-19T09:30:00Z",
            "approved": True,
        }
```

冲突那一处改为同一 key、不同时间：

```python
        conflict = client.post(
            "/internal/agent-tools/reschedule-task",
            headers=internal,
            json={**body, "at": "2026-08-20T09:30:00Z"},
        )
        assert conflict.status_code == 409
```

未确认那一处：

```python
        unapproved = client.post(
            "/internal/agent-tools/reschedule-task",
            headers={**internal, "Idempotency-Key": "update-materials-1"},
            json={
                "task_id": plan["tasks"][1]["id"],
                "expected_version": 1,
                "kind": "delay",
                "at": "2026-08-30T09:30:00Z",
                "approved": False,
            },
        )
```

- [ ] **Step 2: 运行确认失败**

Run: `cd services/api && PYTHONPATH=src python -m pytest tests/integration/agent_access/test_authoring_tools.py tests/integration/agent_access/test_idempotency.py -v`
Expected: 新用例 FAIL（404 / KeyError `change_id`）

- [ ] **Step 3: 仓储加 `get_change_by_version`**

`planning/application/ports.py` 的 `PlanningRepositoryPort` 加：

```python
    async def get_change_by_version(
        self, task_id: UUID, version_after: int
    ) -> TaskChange | None: ...
```

`planning/adapters/outbound/persistence/repositories.py` 的 `SqlAlchemyPlanningRepository` 加（`get_change` 之后），并把 `get_change` 里构造 `TaskChange` 的部分提成模块级函数 `_to_change(model)` 两处共用：

```python
    async def get_change_by_version(
        self, task_id: UUID, version_after: int
    ) -> TaskChange | None:
        """某次写入产生的那条变更。命令只返回 Task，撤销却需要变更本身。"""
        model = await self.session.scalar(
            select(TaskChangeModel).where(
                TaskChangeModel.task_id == task_id,
                TaskChangeModel.version_after == version_after,
            )
        )
        return _to_change(model) if model else None
```

```python
def _to_change(model: TaskChangeModel) -> TaskChange:
    return TaskChange(
        id=model.id,
        task_id=model.task_id,
        operation=model.operation,
        before=_decode_snapshot(model.before_json),
        after=_decode_snapshot(model.after_json),
        version_before=model.version_before,
        version_after=model.version_after,
        changed_by_actor_type=model.changed_by_actor_type,
        changed_by_actor_id=model.changed_by_actor_id,
        created_at=model.created_at,
    )
```

`get_change` 改为 `return _to_change(model) if model else None`。

- [ ] **Step 4: 路由改造**

`router.py`：

1. 删掉 `UpdateTaskRequest`、`_update_task`、`update_task` 端点。
2. 新增请求模型：

```python
class CompleteTaskToolRequest(BaseModel):
    task_id: UUID
    expected_version: int = Field(ge=1)


class RescheduleTaskRequest(BaseModel):
    task_id: UUID
    expected_version: int = Field(ge=1)
    #: schedule = 定下具体去做的时间（例如预约好的产检）；delay = 只把截止时间往后挪。
    kind: Literal["schedule", "delay"]
    at: datetime
    approved: bool = False
```

3. 档位：

```python
DIRECT_EXECUTION_TOOLS = frozenset(
    {"create_task", "create_record", "complete_task", "undo_operation"}
)
```

4. 公共片段与两个 handler（放在原 `_update_task` 的位置）：

```python
async def _task_in_scope(uow, context: AgentToolContext, task_id: UUID):
    task = await uow.repository.get_task(task_id)
    if task is None or task.pregnancy_id != context.pregnancy_id:
        raise ForbiddenError("task is outside the agent pregnancy scope")
    return task


async def _task_write_result(uow, updated) -> dict[str, Any]:
    """写入结果统一带上 change_id：撤销靠它找回这次写入改了什么。"""
    change = await uow.repository.get_change_by_version(updated.id, updated.version)
    return {
        "task_id": str(updated.id),
        "title": updated.title,
        "version": updated.version,
        "status": updated.status.value,
        "change_id": str(change.id) if change else None,
    }


async def _complete_task(session, context: AgentToolContext, body: dict[str, Any]):
    uow = SqlAlchemyPlanningUnitOfWork(session)
    task = await _task_in_scope(uow, context, UUID(body["task_id"]))
    updated = await complete_task.execute(
        CompleteTaskCommand(
            task_id=task.id,
            account_id=context.account_id,
            expected_version=body["expected_version"],
        ),
        uow,
    )
    return (await _task_write_result(uow, updated), f"已完成待办：{updated.title}")


async def _reschedule_task(session, context: AgentToolContext, body: dict[str, Any]):
    uow = SqlAlchemyPlanningUnitOfWork(session)
    task = await _task_in_scope(uow, context, UUID(body["task_id"]))
    at = _parse_datetime(body["at"])
    if body["kind"] == "schedule":
        updated = await schedule_task.execute(
            ScheduleTaskCommand(
                task_id=task.id,
                account_id=context.account_id,
                expected_version=body["expected_version"],
                scheduled_for=at,
            ),
            uow,
        )
    else:
        updated = await delay_task.execute(
            DelayTaskCommand(
                task_id=task.id,
                account_id=context.account_id,
                expected_version=body["expected_version"],
                due_at=at,
            ),
            uow,
        )
    return (await _task_write_result(uow, updated), f"已改期：{updated.title}")
```

5. `_assign_task` 的返回改为：

```python
    return (await _task_write_result(uow, updated), f"已更新任务负责人：{updated.title}")
```

6. 端点：

```python
@router.post("/complete-task", response_model=ToolResult, include_in_schema=False)
async def complete_task_endpoint(request: Request, payload: CompleteTaskToolRequest):
    return await _run(request, "complete_task", payload, _complete_task, write=True)


@router.post("/reschedule-task", response_model=ToolResult, include_in_schema=False)
async def reschedule_task_endpoint(request: Request, payload: RescheduleTaskRequest):
    return await _run(request, "reschedule_task", payload, _reschedule_task, write=True)
```

注意 `CompleteTaskCommand` 名字已被 planning 的命令占用，请求模型因此叫 `CompleteTaskToolRequest`。

- [ ] **Step 5: 运行确认通过**

Run: `cd services/api && PYTHONPATH=src python -m pytest tests/integration/agent_access -v`
Expected: 全部 PASS（`TestDeleteTaskTool` 与 `test_delete_record_removes_it` 暂时仍在、仍通过，下一任务删除）

- [ ] **Step 6: 提交**

```bash
git add services/api/src services/api/tests
git commit -m "feat(api): 完成待办直接执行、改期仍需确认，写入结果带 change_id"
```

---

### Task 4：按操作编号撤销（内部工具 + 公开接口）

**Files:**
- Create: `services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/operation_undo.py`
- Modify: `services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/router.py`
- Modify: `services/api/src/aim_api/bootstrap.py`
- Modify: `contracts/public-api/openapi.json`（生成）
- Create: `services/api/tests/integration/agent_access/test_operation_undo.py`
- Modify: `services/api/tests/integration/agent_access/test_authoring_tools.py`（删 `TestDeleteTaskTool`、`test_delete_record_removes_it`）

**Interfaces:**
- Consumes: Task 2 的 `get_by_operation` / `mark_undone`；Task 3 的 `change_id`、`complete_task` / `reschedule_task`。
- Produces:
  - `async def undo_invocation(session: AsyncSession, invocation: ToolInvocation, *, account_id: UUID) -> tuple[dict[str, Any], str]`
  - 内部端点 `POST /internal/agent-tools/undo-operation`，body `{operation_id}`，直接执行
  - 公开端点 `POST /api/v1/agent/operations/{operation_id}/undo` → `200 {operation_id, summary, already_undone}`；不属于本人 403，不存在 404，不能撤销 409
  - 删除内部端点 `/delete-task`、`/delete-record`

- [ ] **Step 1: 写失败测试**

`services/api/tests/integration/agent_access/test_operation_undo.py`：

```python
from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings

GATEWAY = "/internal/agent-tools"


def _phone(account_id: str) -> str:
    return "138" + str(int(UUID(account_id)) % 10**8).zfill(8)


def _agent(account_id: str, family_id: str, pregnancy_id: str, call_id: str) -> dict[str, str]:
    return {
        "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
        "Actor-Account-Id": account_id,
        "Family-Id": family_id,
        "Pregnancy-Id": pregnancy_id,
        "Eve-Session-Id": f"eve-undo-{account_id}",
        "Idempotency-Key": call_id,
    }


def _scope(client: TestClient):
    account_id = str(uuid4())
    token = issue_session_token(UUID(account_id), _phone(account_id), get_settings().auth_secret)
    public = {"Authorization": f"Bearer {token}"}
    family = client.post(
        "/api/v1/families", headers=public, json={"name": "撤销家庭", "role": "mother"}
    ).json()
    pregnancy = client.post(
        f"/api/v1/families/{family['id']}/pregnancies",
        headers=public,
        json={"due_date": "2027-01-12"},
    ).json()
    client.post(
        f"/api/v1/pregnancies/{pregnancy['id']}/plan",
        headers=public,
        json={"as_of": "2026-08-14"},
    )
    return account_id, family["id"], pregnancy["id"], public


def _tasks(client: TestClient, pregnancy_id: str, public: dict[str, str]) -> dict[str, dict]:
    plan = client.get(f"/api/v1/pregnancies/{pregnancy_id}/plan", headers=public).json()
    return {task["id"]: task for task in plan["tasks"]}


def _undo_tool(client, scope, operation_id: str, call_id: str):
    account_id, family_id, pregnancy_id, _ = scope
    return client.post(
        f"{GATEWAY}/undo-operation",
        headers=_agent(account_id, family_id, pregnancy_id, call_id),
        json={"operation_id": operation_id},
    )


class TestUndoByOperationId:
    def test_undo_create_task_removes_it(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            account_id, family_id, pregnancy_id, public = scope
            created = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent(account_id, family_id, pregnancy_id, "c1"),
                json={"title": "待撤销"},
            ).json()

            response = _undo_tool(client, scope, created["operation_id"], "u1")
            assert response.status_code == 200, response.text
            assert created["data"]["task_id"] not in _tasks(client, pregnancy_id, public)

    def test_undo_complete_restores_status(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            account_id, family_id, pregnancy_id, public = scope
            task_id = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent(account_id, family_id, pregnancy_id, "c2"),
                json={"title": "产检"},
            ).json()["data"]["task_id"]
            completed = client.post(
                f"{GATEWAY}/complete-task",
                headers=_agent(account_id, family_id, pregnancy_id, "c3"),
                json={"task_id": task_id, "expected_version": 1},
            ).json()

            response = _undo_tool(client, scope, completed["operation_id"], "u2")
            assert response.status_code == 200, response.text
            assert _tasks(client, pregnancy_id, public)[task_id]["status"] != "done"

    def test_undo_create_record_hides_it(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            account_id, family_id, pregnancy_id, public = scope
            created = client.post(
                f"{GATEWAY}/create-record",
                headers=_agent(account_id, family_id, pregnancy_id, "c4"),
                json={"record_type": "note", "content": "待撤销"},
            ).json()

            response = _undo_tool(client, scope, created["operation_id"], "u3")
            assert response.status_code == 200, response.text
            records = client.get(
                f"/api/v1/pregnancies/{pregnancy_id}/records", headers=public
            ).json()["records"]
            assert all(record["id"] != created["data"]["record_id"] for record in records)

    def test_undo_twice_is_idempotent(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            account_id, family_id, pregnancy_id, public = scope
            created = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent(account_id, family_id, pregnancy_id, "c5"),
                json={"title": "撤两次"},
            ).json()

            first = _undo_tool(client, scope, created["operation_id"], "u4")
            second = _undo_tool(client, scope, created["operation_id"], "u5")
            assert first.status_code == 200, first.text
            assert second.status_code == 200, second.text
            assert second.json()["data"]["already_undone"] is True

    def test_undo_after_a_later_change_conflicts(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            account_id, family_id, pregnancy_id, public = scope
            task_id = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent(account_id, family_id, pregnancy_id, "c6"),
                json={"title": "后来又改过"},
            ).json()["data"]["task_id"]
            completed = client.post(
                f"{GATEWAY}/complete-task",
                headers=_agent(account_id, family_id, pregnancy_id, "c7"),
                json={"task_id": task_id, "expected_version": 1},
            ).json()
            # 之后用户自己又把它恢复成未完成：原来那次完成已经不是当前变更了。
            client.post(
                f"/api/v1/task-changes/{completed['data']['change_id']}/undo",
                headers=public,
                json={"expected_version": 2},
            )

            response = _undo_tool(client, scope, completed["operation_id"], "u6")
            assert response.status_code == 409, response.text
            assert "之后又被改过" in response.json()["error"]["message"]

    def test_pregnancy_fact_cannot_be_undone(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            account_id, family_id, pregnancy_id, public = scope
            recorded = client.post(
                f"{GATEWAY}/record-pregnancy-fact",
                headers=_agent(account_id, family_id, pregnancy_id, "c8"),
                json={"key": "blood_type", "value": "A", "source": "user_confirmed", "approved": True},
            ).json()

            response = _undo_tool(client, scope, recorded["operation_id"], "u7")
            assert response.status_code == 409, response.text
            assert "孕期信息不能撤销" in response.json()["error"]["message"]


class TestPublicUndoEndpoint:
    def test_owner_can_undo_from_the_card(self) -> None:
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)
            created = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent(account_id, family_id, pregnancy_id, "p1"),
                json={"title": "卡片上撤销"},
            ).json()

            response = client.post(
                f"/api/v1/agent/operations/{created['operation_id']}/undo", headers=public
            )
            assert response.status_code == 200, response.text
            assert response.json()["already_undone"] is False
            assert created["data"]["task_id"] not in _tasks(client, pregnancy_id, public)

    def test_someone_else_cannot_undo(self) -> None:
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)
            _, _, _, other_public = _scope(client)
            created = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent(account_id, family_id, pregnancy_id, "p2"),
                json={"title": "别人的操作"},
            ).json()

            response = client.post(
                f"/api/v1/agent/operations/{created['operation_id']}/undo", headers=other_public
            )
            assert response.status_code == 403, response.text

    def test_unknown_operation_is_404(self) -> None:
        with TestClient(create_app()) as client:
            _, _, _, public = _scope(client)
            response = client.post(f"/api/v1/agent/operations/{uuid4()}/undo", headers=public)
            assert response.status_code == 404, response.text
```

- [ ] **Step 2: 运行确认失败**

Run: `cd services/api && PYTHONPATH=src python -m pytest tests/integration/agent_access/test_operation_undo.py -v`
Expected: FAIL（422：`undo-operation` 还要 `change_id`；公开端点 404）

- [ ] **Step 3: 反向逻辑与公开端点**

`services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/operation_undo.py`：

```python
"""按操作编号撤销 AIM 做过的一次写入。

模型和卡片上的「撤销」按钮都走这里：每个写工具的结果里本来就有 operation_id，
服务端也逐条存了调用记录，所以撤销不需要模型记住任何别的 ID。
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Request
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from aim_api.contexts.agent_access.adapters.outbound.persistence.repositories import (
    SqlAlchemyToolInvocationRepository,
)
from aim_api.contexts.agent_access.domain.tool_invocation import (
    ToolInvocation,
    ToolInvocationStatus,
)
from aim_api.contexts.planning.adapters.outbound.persistence.repositories import (
    SqlAlchemyPlanningUnitOfWork,
)
from aim_api.contexts.planning.application.commands import delete_task, undo_change
from aim_api.contexts.planning.application.commands.delete_task import DeleteTaskCommand
from aim_api.contexts.planning.application.commands.undo_change import UndoChangeCommand
from aim_api.contexts.planning.domain.task_status import (
    InvalidTaskTransition,
    TaskVersionConflict,
)
from aim_api.contexts.records.adapters.outbound.persistence.repositories import (
    SqlAlchemyRecordsUnitOfWork,
)
from aim_api.contexts.records.application.commands import delete_record
from aim_api.contexts.records.application.commands.delete_record import DeleteRecordCommand
from aim_api.contexts.records.domain.errors import RecordNotFound
from aim_api.platform.auth.context import authenticate_active
from aim_api.platform.http.errors import ConflictError, ForbiddenError, NotFoundError

#: 撤销「新建」即删除；撤销对待办的修改即还原那条 task change。
_DELETE_TASK = {"create_task"}
_DELETE_RECORD = {"create_record", "create_knowledge"}
_REVERT_CHANGE = {"complete_task", "reschedule_task", "assign_task"}


async def undo_invocation(
    session: AsyncSession, invocation: ToolInvocation, *, account_id: UUID
) -> tuple[dict[str, Any], str]:
    if invocation.account_id is None or invocation.account_id != account_id:
        raise ForbiddenError("这次操作不属于当前账号")
    if invocation.status is not ToolInvocationStatus.completed:
        raise ConflictError("这次操作没有执行，不需要撤销")

    base = {"operation_id": str(invocation.operation_id)}
    if invocation.undone_at is not None:
        return ({**base, "already_undone": True}, "这次操作已经撤销过了")

    tool = invocation.tool_name
    data = invocation.result.get("data", {})
    if tool == "record_pregnancy_fact":
        raise ConflictError("孕期信息不能撤销，直接告诉我正确的值即可")

    if tool in _DELETE_TASK:
        await delete_task.execute(
            DeleteTaskCommand(
                task_id=UUID(data["task_id"]),
                pregnancy_id=invocation.pregnancy_id,
                account_id=account_id,
            ),
            SqlAlchemyPlanningUnitOfWork(session),
        )
        summary = "已撤销新建的待办"
    elif tool in _DELETE_RECORD:
        try:
            await delete_record.execute(
                DeleteRecordCommand(
                    record_id=UUID(data["record_id"]),
                    family_id=invocation.family_id,
                    account_id=account_id,
                    pregnancy_id=invocation.pregnancy_id,
                ),
                SqlAlchemyRecordsUnitOfWork(session),
            )
        except RecordNotFound:
            # 用户已经在别处删掉了：撤销想要的结果已经达成。
            pass
        summary = "已撤销新建的记录"
    elif tool in _REVERT_CHANGE:
        change_id = data.get("change_id")
        if not change_id:
            raise ConflictError("这次操作缺少变更记录，不能撤销")
        uow = SqlAlchemyPlanningUnitOfWork(session)
        change = await uow.repository.get_change(UUID(change_id))
        if change is None:
            raise ConflictError("这项待办已经不存在了")
        try:
            updated = await undo_change.execute(
                UndoChangeCommand(
                    change_id=change.id,
                    account_id=account_id,
                    expected_version=change.version_after,
                ),
                uow,
            )
        except (TaskVersionConflict, InvalidTaskTransition) as error:
            await session.rollback()
            raise ConflictError("这项待办之后又被改过，不能直接撤销") from error
        summary = f"已撤销：{updated.title}"
    else:
        raise ConflictError("这类操作不能撤销")

    invocations = SqlAlchemyToolInvocationRepository(session)
    await invocations.mark_undone(invocation.operation_id, datetime.now(UTC))
    await session.commit()
    return ({**base, "already_undone": False}, summary)


router = APIRouter(tags=["agent-operations"])


class UndoOperationResponse(BaseModel):
    operation_id: UUID
    summary: str
    already_undone: bool


@router.post(
    "/api/v1/agent/operations/{operation_id}/undo", response_model=UndoOperationResponse
)
async def undo_operation_from_card(operation_id: UUID, request: Request) -> UndoOperationResponse:
    """对话卡片上的「撤销」。与模型调用的 undo_operation 共用同一套反向逻辑。"""
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        invocation = await SqlAlchemyToolInvocationRepository(session).get_by_operation(
            operation_id
        )
        if invocation is None:
            raise NotFoundError("没有找到这次操作")
        data, summary = await undo_invocation(session, invocation, account_id=actor.account_id)
    return UndoOperationResponse(
        operation_id=operation_id, summary=summary, already_undone=data["already_undone"]
    )
```

- [ ] **Step 4: 内部 `undo-operation` 改收 operation_id，删掉两个删除端点**

`router.py`：

1. `UndoOperationRequest` 改为：

```python
class UndoOperationRequest(BaseModel):
    operation_id: UUID
```

2. `_undo_operation` 改为：

```python
async def _undo_operation(session, context: AgentToolContext, body: dict[str, Any]):
    invocation = await SqlAlchemyToolInvocationRepository(session).get_by_operation(
        UUID(body["operation_id"])
    )
    if invocation is None or invocation.pregnancy_id != context.pregnancy_id:
        raise ConflictError("没有找到这次操作，可能不是在这段孕期里做的")
    return await undo_invocation(session, invocation, account_id=context.account_id)
```

并在文件头 `from ...operation_undo import undo_invocation`。

3. 删除 `DeleteTaskRequest`、`DeleteRecordRequest`、`_delete_task`、`_delete_record`、`delete_task_endpoint`、`delete_record_endpoint`，以及不再使用的 import（`delete_task`、`DeleteTaskCommand`、`delete_record`、`DeleteRecordCommand`、`undo_change`、`UndoChangeCommand`——以 `ruff check` 报告为准）。

- [ ] **Step 5: 注册公开路由**

`bootstrap.py` 在 `agent_sessions_router` 的 import 旁边加：

```python
from aim_api.contexts.agent_access.adapters.inbound.http.operation_undo import (
    router as agent_operations_router,
)
```

在 `app.include_router(agent_sessions_router)` 下一行加 `app.include_router(agent_operations_router)`。

- [ ] **Step 6: 删掉过时的删除测试**

`test_authoring_tools.py` 删除整个 `TestDeleteTaskTool` 类和 `TestCreateRecordTool.test_delete_record_removes_it`（撤销覆盖已移到 `test_operation_undo.py`）。

- [ ] **Step 7: 运行确认通过**

Run: `cd services/api && PYTHONPATH=src python -m pytest tests/integration/agent_access -v`
Expected: 全部 PASS

- [ ] **Step 8: 重新生成契约并跑全量**

```bash
make -C services/api contracts
make -C services/api test
make -C services/api lint
```

Expected: `contracts/public-api/openapi.json` 多出 `/api/v1/agent/operations/{operation_id}/undo`；测试与 lint 全绿。

- [ ] **Step 9: 提交**

```bash
git add services/api contracts
git commit -m "feat(api): 按操作编号撤销 AIM 的写入，卡片可经公开接口撤销"
```

---

### Task 5：孕期上下文带上家庭成员

**Files:**
- Modify: `services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/router.py`（`_get_context`）
- Create: `services/api/tests/integration/agent_access/test_pregnancy_context_tool.py`

**Interfaces:**
- Produces: `get-pregnancy-context` 的 `data` 增加 `self_member_id: str` 与 `members: [{member_id, display_name, role}]`（只含 `active` 成员；`member_id` 即账号 ID，`assign_task` 的 `assigned_member_id` 用它）。

- [ ] **Step 1: 写失败测试**

```python
from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings


def _phone(account_id: str) -> str:
    return "138" + str(int(UUID(account_id)) % 10**8).zfill(8)


def test_context_lists_active_members_so_assign_can_work() -> None:
    account_id = str(uuid4())
    token = issue_session_token(UUID(account_id), _phone(account_id), get_settings().auth_secret)
    public = {"Authorization": f"Bearer {token}"}
    with TestClient(create_app()) as client:
        family = client.post(
            "/api/v1/families", headers=public, json={"name": "成员家庭", "role": "mother"}
        ).json()
        pregnancy = client.post(
            f"/api/v1/families/{family['id']}/pregnancies",
            headers=public,
            json={"due_date": "2027-01-12"},
        ).json()
        response = client.post(
            "/internal/agent-tools/get-pregnancy-context",
            headers={
                "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
                "Actor-Account-Id": account_id,
                "Family-Id": family["id"],
                "Pregnancy-Id": pregnancy["id"],
                "Eve-Session-Id": f"eve-context-{account_id}",
                "Idempotency-Key": "ctx-1",
            },
            json={},
        )
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    assert data["self_member_id"] == account_id
    assert data["members"] == [
        {"member_id": account_id, "display_name": "妈妈", "role": "mother"}
    ]
```

- [ ] **Step 2: 运行确认失败**

Run: `cd services/api && PYTHONPATH=src python -m pytest tests/integration/agent_access/test_pregnancy_context_tool.py -v`
Expected: FAIL，`KeyError: 'self_member_id'`

- [ ] **Step 3: 实现**

`router.py` 加常量与改 `_get_context`：

```python
#: 称呼为空时的回退，与 iOS 家庭页一致。
_ROLE_NAMES = {"mother": "妈妈", "father": "爸爸", "other_caregiver": "家人"}


async def _get_context(session, context: AgentToolContext, body: dict[str, Any]):
    pregnancy = await SqlAlchemyPregnancyRepository(session).get_pregnancy(context.pregnancy_id)
    plan = await SqlAlchemyPlanningUnitOfWork(session).repository.get_plan(context.pregnancy_id)
    family = await SqlAlchemyFamilyRepository(session).get_family(context.family_id)
    age = pregnancy.gestational_age() if pregnancy else None
    members = [
        {
            "member_id": str(member.account_id),
            "display_name": (member.nickname or "").strip()
            or _ROLE_NAMES.get(member.role.value, "家人"),
            "role": member.role.value,
        }
        for member in (family.members.values() if family else [])
        if member.status.value == "active"
    ]
    return (
        {
            "family_id": str(context.family_id),
            "pregnancy_id": str(context.pregnancy_id),
            "due_date": pregnancy.due_date.isoformat() if pregnancy else None,
            "gestational_age": {"weeks": age.weeks, "days": age.days} if age else None,
            "plan_id": str(plan.id) if plan else None,
            "self_member_id": str(context.account_id),
            "members": members,
        },
        "已读取当前孕期上下文",
    )
```

- [ ] **Step 4: 运行确认通过**

Run: `cd services/api && PYTHONPATH=src python -m pytest tests/integration/agent_access -v`
Expected: 全部 PASS

- [ ] **Step 5: 提交**

```bash
git add services/api
git commit -m "feat(api): 孕期上下文带上家庭成员，指派待办有了可用的成员 ID"
```

---

### Task 6：Eve 工具按档位重组

**Files:**
- Create: `services/agent/agent/tools/complete_task.ts`、`services/agent/agent/tools/reschedule_task.ts`
- Modify: `services/agent/agent/tools/undo_operation.ts`、`create_record.ts`、`assign_task.ts`
- Delete: `services/agent/agent/tools/update_task.ts`、`delete_task.ts`、`delete_record.ts`、`preview_task_change.ts`
- Modify: `services/agent/agent/lib/auth/session-context.ts`
- Modify: `services/agent/tests/tools/authoring.test.ts`、`tests/plan-change-flow.test.ts`、`tests/runtime-gate.test.ts`

**Interfaces:**
- Consumes: Task 3/4/5 的内部端点。
- Produces（模型可见的工具）：
  - `complete_task({ taskId, expectedVersion })` → `/complete-task`，无确认
  - `reschedule_task({ taskId, expectedVersion, kind: "schedule"|"delay", at })` → `/reschedule-task`，`approval: always()`
  - `undo_operation({ operationId })` → `/undo-operation`，无确认
  - `create_record({ recordType, … })` 按类型带字段
  - 缺孕期档案时所有业务工具抛 `还没有建立孕期档案，请先在 App 里填写预产期或末次月经`

- [ ] **Step 1: 改写测试**

`tests/plan-change-flow.test.ts` 整个替换为：

```ts
import assert from "node:assert/strict";
import test from "node:test";
import completeTask from "../agent/tools/complete_task.ts";
import rescheduleTask from "../agent/tools/reschedule_task.ts";
import undoOperation from "../agent/tools/undo_operation.ts";

const ctx = {
  session: {
    id: "wrun_write_session",
    auth: {
      current: {
        attributes: { accountId: "acct_test", familyId: "fam_test", pregnancyId: "preg_test" },
      },
    },
  },
  callId: "call_write_001",
  abortSignal: AbortSignal.timeout(2_000),
} as never;

async function capture(run: () => unknown): Promise<Request> {
  const previousSecret = process.env.AGENT_SERVICE_SECRET;
  const previousBaseUrl = process.env.AIM_API_INTERNAL_URL;
  const previousFetch = globalThis.fetch;
  process.env.AGENT_SERVICE_SECRET = "test-agent-secret";
  process.env.AIM_API_INTERNAL_URL = "http://api.test";
  let request: Request | undefined;
  globalThis.fetch = async (input, init) => {
    request = new Request(input, init);
    return new Response(
      JSON.stringify({ operation_id: "op_1", status: "completed", summary: "ok", data: {} }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };
  try {
    await (run() as Promise<unknown>);
  } finally {
    globalThis.fetch = previousFetch;
    if (previousSecret === undefined) delete process.env.AGENT_SERVICE_SECRET;
    else process.env.AGENT_SERVICE_SECRET = previousSecret;
    if (previousBaseUrl === undefined) delete process.env.AIM_API_INTERNAL_URL;
    else process.env.AIM_API_INTERNAL_URL = previousBaseUrl;
  }
  assert.ok(request);
  return request;
}

const TASK = "00000000-0000-4000-8000-000000000001";

test("complete_task executes directly", async () => {
  assert.equal(completeTask.approval, undefined);
  const request = await capture(() =>
    completeTask.execute({ taskId: TASK, expectedVersion: 1 }, ctx),
  );
  assert.equal(request.url, "http://api.test/internal/agent-tools/complete-task");
  assert.deepEqual(await request.json(), { task_id: TASK, expected_version: 1 });
});

test("reschedule_task is gated and forwards server approval", async () => {
  assert.equal(typeof rescheduleTask.approval, "function");
  const request = await capture(() =>
    rescheduleTask.execute(
      { taskId: TASK, expectedVersion: 2, kind: "delay", at: "2026-10-09T09:00:00.000Z" },
      ctx,
    ),
  );
  assert.equal(request.url, "http://api.test/internal/agent-tools/reschedule-task");
  assert.deepEqual(await request.json(), {
    task_id: TASK,
    expected_version: 2,
    kind: "delay",
    at: "2026-10-09T09:00:00.000Z",
    approved: true,
  });
});

test("undo_operation needs only the operation id and no approval", async () => {
  assert.equal(undoOperation.approval, undefined);
  const request = await capture(() =>
    undoOperation.execute({ operationId: "11111111-1111-4111-8111-111111111111" }, ctx),
  );
  assert.equal(request.url, "http://api.test/internal/agent-tools/undo-operation");
  assert.deepEqual(await request.json(), {
    operation_id: "11111111-1111-4111-8111-111111111111",
  });
});

test("tools refuse to run without a pregnancy profile, in Chinese", async () => {
  const noPregnancy = {
    ...(ctx as object),
    session: {
      id: "wrun_x",
      auth: { current: { attributes: { accountId: "a", familyId: "f", pregnancyId: "" } } },
    },
  } as never;
  await assert.rejects(
    () => completeTask.execute({ taskId: TASK, expectedVersion: 1 }, noPregnancy) as Promise<unknown>,
    /还没有建立孕期档案/,
  );
});
```

`tests/tools/authoring.test.ts`：
- import 删掉 `deleteTask`、`updateTask`；
- `"create_task is not gated by an approval request"` 里删掉 `deleteTask` 那行；
- 删掉 `"update_task keeps its approval gate"` 和 `"delete_task targets the undo endpoint"` 两个用例；
- 追加：

```ts
test("create_record builds symptom structured data from typed fields", async () => {
  const { request } = await withStubbedApi({ record_id: "r1" }, () =>
    createRecord.execute(
      { recordType: "symptom", symptoms: ["头晕", "恶心"], severity: 3 },
      scope,
    ),
  );
  const body = (await request?.clone().json()) as Record<string, unknown>;
  assert.equal(body.record_type, "symptom");
  assert.deepEqual(body.structured_data, { symptoms: ["头晕", "恶心"], severity: 3 });
});

test("create_record fills the four checkup text fields and keeps metrics", async () => {
  const { request } = await withStubbedApi({ record_id: "r2" }, () =>
    createRecord.execute(
      {
        recordType: "checkup",
        hospital: "杭州市妇产科医院",
        metrics: { systolic: 118, diastolic: 76 },
      },
      scope,
    ),
  );
  const body = (await request?.clone().json()) as Record<string, unknown>;
  assert.deepEqual(body.structured_data, {
    hospital: "杭州市妇产科医院",
    exam_items: "",
    result: "",
    doctor_advice: "",
    metrics: { systolic: 118, diastolic: 76 },
  });
});

test("create_record rejects a symptom without symptoms before calling the API", async () => {
  await assert.rejects(
    () => createRecord.execute({ recordType: "symptom", severity: 2 }, scope) as Promise<unknown>,
    /至少写一个症状/,
  );
});
```

`tests/runtime-gate.test.ts` 的 `BUSINESS_TOOLS` 改为：

```ts
  const BUSINESS_TOOLS = [
    "assign_task",
    "complete_task",
    "create_knowledge",
    "create_record",
    "create_task",
    "echo_context",
    "get_current_time",
    "get_guidance",
    "get_pregnancy_context",
    "list_records",
    "list_tasks",
    "record_pregnancy_fact",
    "reschedule_task",
    "undo_operation",
  ];

  // 撤销只走 undo_operation；这几个要么是任意删除的口子，要么是空壳。
  const RETIRED_TOOLS = ["delete_record", "delete_task", "preview_task_change", "update_task"];
```

并在 `DANGEROUS_TOOLS` 的循环之后加：

```ts
  for (const name of RETIRED_TOOLS) {
    assert.ok(!exposed.includes(name), `${name} 已下线，不该再暴露`);
  }
```

同文件末尾那个检查 `preview_task_change` 事件的用例（约 177 行，依赖 `EVE_RUNTIME_URL`，默认 skip）：把断言里的 `preview_task_change` 换成 `get_pregnancy_context`。

- [ ] **Step 2: 运行确认失败**

Run: `cd services/agent && npm test`
Expected: FAIL（找不到 `complete_task.ts` 等模块）

- [ ] **Step 3: 新工具**

`agent/tools/complete_task.ts`：

```ts
import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 「直接执行」档：完成是最常见的一句话操作（「产检做完了」），每次都确认太烦，
// 做错了由 undo_operation 撤回。档位同时在服务端 DIRECT_EXECUTION_TOOLS 声明。
export default defineTool({
  description:
    "Mark one to-do as done when the user says it is finished. Executes immediately; " +
    "tell the user it can be undone. Read list_tasks first to get taskId and version.",
  inputSchema: z.object({
    taskId: z.string().uuid(),
    expectedVersion: z.number().int().min(1),
  }),
  outputSchema: toolResultSchema,
  async execute({ taskId, expectedVersion }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/complete-task", {
      task_id: taskId,
      expected_version: expectedVersion,
    });
  },
});
```

`agent/tools/reschedule_task.ts`：

```ts
import { defineTool } from "eve/tools";
import { always } from "eve/tools/approval";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description:
    "Change when a to-do happens. kind=schedule sets a concrete time the user will do it " +
    "(e.g. a booked checkup); kind=delay only pushes the deadline later. " +
    "The user confirms on a card before it runs.",
  inputSchema: z.object({
    taskId: z.string().uuid(),
    expectedVersion: z.number().int().min(1),
    kind: z.enum(["schedule", "delay"]),
    at: z.string().datetime(),
  }),
  outputSchema: toolResultSchema,
  approval: always(),
  async execute({ taskId, expectedVersion, kind, at }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/reschedule-task", {
      task_id: taskId,
      expected_version: expectedVersion,
      kind,
      at,
      // Eve 只在确认通过后才调用 execute。
      approved: true,
    });
  },
});
```

`agent/tools/undo_operation.ts` 整个替换为：

```ts
import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 撤销本身就是用户的明确意思，不再二次确认。
export default defineTool({
  description:
    "Undo something you did earlier in this conversation. Pass the operationId from that " +
    "tool's result. Works for created to-dos and records, completed or rescheduled to-dos, " +
    "and assignments. Pregnancy facts cannot be undone.",
  inputSchema: z.object({ operationId: z.string().uuid() }),
  outputSchema: toolResultSchema,
  async execute({ operationId }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/undo-operation", {
      operation_id: operationId,
    });
  },
});
```

`agent/tools/assign_task.ts` 的 `description` 改为：

```ts
  description:
    "Assign a to-do to a family member. Use a member_id from get_pregnancy_context.members " +
    "(or null to unassign). The user confirms on a card before it runs.",
```

- [ ] **Step 4: `create_record` 按类型带字段**

`agent/tools/create_record.ts` 整个替换为：

```ts
import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 「直接执行」档，同 create_task。
//
// 字段平铺而不是用判别联合：OpenAI 兼容的函数调用要求顶层是 object，
// 顶层 anyOf 会被部分提供方拒收。按类型该填哪些，写在各字段的 describe 里，
// 缺了在这里先拦下，错误信息回到模型手里让它补。
const metrics = z
  .object({
    weight_kg: z.number().optional(),
    systolic: z.number().optional(),
    diastolic: z.number().optional(),
    fasting_glucose: z.number().optional(),
    hemoglobin: z.number().optional(),
  })
  .describe("checkup only. Units: kg, mmHg, mmol/L, g/L.");

export default defineTool({
  description:
    "Record something for the family: a note, a symptom, or a checkup result. " +
    "Use this when the user wants to write something down or remember how they felt.",
  inputSchema: z.object({
    recordType: z.enum(["symptom", "checkup", "note"]),
    title: z.string().max(200).optional(),
    content: z.string().max(4000).optional().describe("note only: the text to keep."),
    symptoms: z.array(z.string().min(1)).optional().describe("symptom only: at least one."),
    severity: z.number().int().min(1).max(5).optional().describe("symptom only: 1 mild … 5 severe."),
    symptomNote: z.string().max(1000).optional().describe("symptom only: extra detail."),
    hospital: z.string().optional().describe("checkup only."),
    examItems: z.string().optional().describe("checkup only: what was examined."),
    result: z.string().optional().describe("checkup only: the findings."),
    doctorAdvice: z.string().optional().describe("checkup only."),
    metrics: metrics.optional(),
    occurredAt: z.iso.datetime().optional(),
  }),
  outputSchema: toolResultSchema,
  async execute(input, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/create-record", {
      record_type: input.recordType,
      title: input.title,
      content: input.recordType === "note" ? input.content : undefined,
      structured_data: structuredDataFor(input),
      occurred_at: input.occurredAt,
    });
  },
});

type RecordInput = {
  recordType: "symptom" | "checkup" | "note";
  symptoms?: string[];
  severity?: number;
  symptomNote?: string;
  hospital?: string;
  examItems?: string;
  result?: string;
  doctorAdvice?: string;
  metrics?: Record<string, number | undefined>;
};

function structuredDataFor(input: RecordInput): Record<string, unknown> {
  if (input.recordType === "symptom") {
    if (!input.symptoms?.length) throw new Error("症状记录至少写一个症状（symptoms）");
    if (input.severity === undefined) throw new Error("症状记录需要严重程度 severity（1–5）");
    return {
      symptoms: input.symptoms,
      severity: input.severity,
      ...(input.symptomNote ? { note: input.symptomNote } : {}),
    };
  }
  if (input.recordType === "checkup") {
    // 后端要求这四项都是字符串（可以为空），指标名只能取固定的几种。
    const cleanMetrics = Object.fromEntries(
      Object.entries(input.metrics ?? {}).filter(([, value]) => value !== undefined),
    );
    return {
      hospital: input.hospital ?? "",
      exam_items: input.examItems ?? "",
      result: input.result ?? "",
      doctor_advice: input.doctorAdvice ?? "",
      ...(Object.keys(cleanMetrics).length ? { metrics: cleanMetrics } : {}),
    };
  }
  return {};
}
```

- [ ] **Step 5: 无孕期档案的中文错误**

`agent/lib/auth/session-context.ts` 的 `requireAimScope` 改为：

```ts
export function requireAimScope(ctx: AuthenticatedSessionContext): AimScope {
  const attributes = ctx.session.auth.current?.attributes;
  const pregnancyId = attributes?.pregnancyId;
  // 鉴权时没有孕期档案的账号 pregnancyId 为空串（见 lib/auth.ts）。这句话会回到
  // 模型手里并被转述给用户，所以写成用户能照着做的中文。
  if (typeof pregnancyId !== "string" || pregnancyId.trim().length === 0) {
    throw new Error("还没有建立孕期档案，请先在 App 里填写预产期或末次月经");
  }
  return {
    accountId: requiredAttribute(attributes, "accountId"),
    familyId: requiredAttribute(attributes, "familyId"),
    pregnancyId: pregnancyId.trim(),
  };
}
```

- [ ] **Step 6: 删掉下线的工具**

```bash
cd services/agent
git rm agent/tools/update_task.ts agent/tools/delete_task.ts agent/tools/delete_record.ts agent/tools/preview_task_change.ts
```

- [ ] **Step 7: 构建并运行测试**

Run: `cd services/agent && npm run build && npm test && npm run lint`
Expected: 全部 PASS

- [ ] **Step 8: 提交**

```bash
git add services/agent
git commit -m "feat(agent): 完成与改期分档、撤销只收操作编号，下线任意删除与空壳预览"
```

---

### Task 7：系统指令与技能跟上新档位

**Files:**
- Modify: `services/agent/agent/instructions.md`
- Modify: `services/agent/agent/skills/adjust-pregnancy-plan/SKILL.md`

**Interfaces:**
- Consumes: Task 6 的工具名。

- [ ] **Step 1: 改 `instructions.md` 最后一段**

把从 `Use \`get_pregnancy_context\`, \`list_tasks\`…` 开始到文件末尾，替换为：

```markdown
Use `get_pregnancy_context`, `list_tasks`, `list_records`, and `get_guidance`
for current facts. When the user asks about a recent symptom, checkup, or note,
read the relevant records first and distinguish what was recorded from what is
your interpretation. Do not diagnose or turn a recorded symptom into a medical
conclusion; for urgent or red-flag symptoms, recommend contacting a qualified
medical provider promptly.

Writes come in two tiers, decided by the business service:

- Done immediately, undoable: `create_task`, `create_record`, `complete_task`,
  `undo_operation`. Just do it, then say in one short sentence what you did and
  that it can be undone.
- Confirmed by the user on a card first: `reschedule_task`, `assign_task`,
  `record_pregnancy_fact`, `create_knowledge`. Call the tool directly — the app
  shows the card. Do not ask "shall I?" in text first; that makes the user
  confirm twice.

To undo, call `undo_operation` with the `operationId` from the earlier tool
result. Pregnancy facts cannot be undone; ask the user for the correct value
instead. To assign, use a `member_id` from `get_pregnancy_context.members`.
Always use the `expectedVersion` you just read; on a version conflict, read the
task again and explain. The business API is the source of truth; never claim a
write succeeded from an assistant sentence alone.
Load the `adjust-pregnancy-plan` skill when a user asks to change a plan.
```

- [ ] **Step 2: 改技能**

`SKILL.md` 的编号列表替换为：

```markdown
1. 先读取孕期上下文和当前任务，不要根据对话记忆猜测任务版本、孕周或家庭成员。
2. 解释任务为什么出现在当前阶段。
3. 完成待办直接调用 `complete_task`；改期用 `reschedule_task`，指派用 `assign_task`——这两个会在 App 里弹确认卡，不要先用文字问一遍。
4. 写工具必须使用刚读到的 `expectedVersion`；遇到版本冲突重新读取任务并向用户说明。
5. 用户说「撤销」「刚才那个不对」时，用上一次写工具返回的 `operationId` 调 `undo_operation`。
6. 以工具返回的结果为准，不从自己的文字推断业务事实。
```

- [ ] **Step 3: 构建确认指令与技能能编译**

Run: `cd services/agent && npm run build && npm test`
Expected: PASS

- [ ] **Step 4: 提交**

```bash
git add services/agent/agent/instructions.md services/agent/agent/skills
git commit -m "docs(agent): 指令与技能改为新的确认档位与按操作编号撤销"
```

---

### Task 8：线上缺配置时拒绝启动

**Files:**
- Modify: `services/agent/agent/lib/model-config.ts`
- Modify: `services/agent/agent/agent.ts`
- Modify: `services/agent/tests/model-config.test.ts`
- Modify: `infrastructure/compose/compose.prod.yaml`
- Modify: `infrastructure/deploy/README.md`

**Interfaces:**
- Produces: `resolveAgentModelConfig(env)` 在 `env.AIM_DEPLOYMENT === "production"` 且会落到 mock 时抛错；`agent.ts` 模块加载时调用一次。

- [ ] **Step 1: 写失败测试**

`tests/model-config.test.ts` 末尾追加：

```ts
test("production refuses to fall back to the mock model", () => {
  assert.throws(
    () => resolveAgentModelConfig({ AIM_DEPLOYMENT: "production" }),
    /AIM_DEPLOYMENT=production/,
  );
  assert.throws(
    () => resolveAgentModelConfig({ AIM_DEPLOYMENT: "production", EVE_USE_MOCK_MODEL: "1" }),
    /AIM_DEPLOYMENT=production/,
  );
});

test("production with a real model configured is fine", () => {
  const config = resolveAgentModelConfig({
    AIM_DEPLOYMENT: "production",
    EVE_USE_MOCK_MODEL: "0",
    DEEPSEEK_API_KEY: "k",
  });
  assert.equal(config.kind, "deepseek");
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd services/agent && node --test tests/model-config.test.ts`
Expected: FAIL（第一条返回了 `{ kind: "mock" }`）

- [ ] **Step 3: 实现**

`model-config.ts` 的 `resolveAgentModelConfig` 开头改为：

```ts
export function resolveAgentModelConfig(env: Environment = process.env): AgentModelConfig {
  if (env.EVE_USE_MOCK_MODEL !== "0") {
    // 线上漏配一个变量就退回 mock，用户会收到一句英文的 "runtime is ready"。
    // 宁可起不来，也不要看起来正常。
    if (env.AIM_DEPLOYMENT === "production") {
      throw new Error(
        "AIM_DEPLOYMENT=production requires EVE_USE_MOCK_MODEL=0 and DEEPSEEK_API_KEY",
      );
    }
    return { kind: "mock" };
  }
```

`agent/agent.ts` 顶部 import 后加一行，让配置错误在进程启动时就暴露，而不是等到第一次对话：

```ts
import { resolveAgentModelConfig } from "./lib/model-config";

resolveAgentModelConfig();
```

- [ ] **Step 4: 运行确认通过**

Run: `cd services/agent && npm run build && npm test`
Expected: PASS（本地没有 `AIM_DEPLOYMENT`，build 不受影响）

- [ ] **Step 5: 生产 compose 与部署文档**

`compose.prod.yaml` 的 `eve:` 下加：

```yaml
    environment:
      AIM_DEPLOYMENT: production
      EVE_USE_MOCK_MODEL: "0"
```

（若该服务已有 `environment:` 键，合并进去。）

`infrastructure/deploy/README.md` 在环境变量说明处加一句：

```markdown
- `AIM_DEPLOYMENT=production` 由 `compose.prod.yaml` 设置。此时 `.env` 里必须有 `DEEPSEEK_API_KEY`，否则 eve 容器启动即退出——这是有意的，缺配置时不能静默退回 mock 模型。
```

- [ ] **Step 6: 验证 compose 合并结果**

Run: `cd infrastructure/compose && docker compose -f compose.yaml -f compose.prod.yaml config | grep -A3 AIM_DEPLOYMENT`
Expected: 输出里 eve 服务带 `AIM_DEPLOYMENT: production` 与 `EVE_USE_MOCK_MODEL: "0"`

- [ ] **Step 7: 提交**

```bash
git add services/agent infrastructure
git commit -m "fix(agent): 生产环境缺模型配置时拒绝启动，不再静默退回 mock"
```

---

### Task 9：确认按钮按消息出现、按工具写文案、提交失败可重试

**Files:**
- Create: `apps/agent-web/src/approvalBatch.ts`、`apps/agent-web/src/approvalBatch.test.ts`
- Modify: `apps/agent-web/src/approvals.tsx`
- Modify: `apps/agent-web/src/tools/labels.ts`、`apps/agent-web/src/tools/labels.test.ts`（新建）
- Modify: `apps/agent-web/src/tools/types.ts`、`ToolGroup.tsx`、`ToolCard.tsx`
- Modify: `apps/agent-web/src/App.tsx`（`AssistantMessage`）

**Interfaces:**
- Produces:
  - `approvalBatch.ts`：`nextDispatch(pending: string[], decisions: Map<string, {approved: boolean}>, dispatched: Set<string>): { key: string; payload: {requestId: string; approved: boolean}[] } | null`
  - `labels.ts`：`approvalCopy(toolNames: string[]): { confirm: string; reject: string; pendingYes: string; pendingNo: string; rejected: string }`
  - `types.ts`：`pendingApprovalTools(parts: readonly unknown[]): string[]`
  - `useApprovalBatch()` 增加 `error: string | null` 与 `retry(): void`
  - `ToolGroupActions({ toolNames })`、`ApprovalSlot` / `ToolStatusLine` 用 `approvalCopy([props.toolName])`

- [ ] **Step 1: 写失败测试**

`apps/agent-web/src/approvalBatch.test.ts`：

```ts
import { describe, expect, test } from "vitest";
import { nextDispatch } from "./approvalBatch";

const d = (approved: boolean) => ({ approved });

describe("nextDispatch", () => {
  test("waits until every pending approval has a decision", () => {
    expect(nextDispatch(["a", "b"], new Map([["a", d(true)]]), new Set())).toBeNull();
  });

  test("sends the whole batch once all are decided", () => {
    const result = nextDispatch(["b", "a"], new Map([["a", d(true)], ["b", d(false)]]), new Set());
    expect(result).toEqual({
      key: "a|b",
      payload: [
        { requestId: "b", approved: false },
        { requestId: "a", approved: true },
      ],
    });
  });

  test("does not resend a batch already dispatched", () => {
    expect(
      nextDispatch(["a"], new Map([["a", d(true)]]), new Set(["a"])),
    ).toBeNull();
  });

  test("nothing pending means nothing to send", () => {
    expect(nextDispatch([], new Map(), new Set())).toBeNull();
  });
});
```

`apps/agent-web/src/tools/labels.test.ts`：

```ts
import { expect, test } from "vitest";
import { approvalCopy } from "./labels";

test("each gated tool gets its own verbs", () => {
  expect(approvalCopy(["reschedule_task"]).confirm).toBe("确认改期");
  expect(approvalCopy(["assign_task"]).confirm).toBe("确认指派");
  expect(approvalCopy(["record_pregnancy_fact"]).confirm).toBe("确认更新");
  expect(approvalCopy(["create_knowledge"]).confirm).toBe("收录");
});

test("mixed batches fall back to neutral wording", () => {
  const copy = approvalCopy(["reschedule_task", "assign_task"]);
  expect(copy.confirm).toBe("确认");
  expect(copy.reject).toBe("取消");
});

test("nothing says 收录 unless the batch is only knowledge", () => {
  for (const name of ["reschedule_task", "assign_task", "record_pregnancy_fact", "unknown_tool"]) {
    const copy = approvalCopy([name]);
    expect(Object.values(copy).join("")).not.toContain("收录");
  }
});
```

`apps/agent-web/src/tools/types.test.ts`：

```ts
import { expect, test } from "vitest";
import { pendingApprovalTools } from "./types";

test("only tool calls still awaiting a decision count", () => {
  const parts = [
    { type: "text", text: "好的" },
    { type: "tool-call", toolName: "reschedule_task", approval: { id: "1" } },
    { type: "tool-call", toolName: "assign_task", approval: { id: "2", approved: true } },
    { type: "tool-call", toolName: "create_knowledge", approval: { id: "3", resolution: "expired" } },
    { type: "tool-call", toolName: "list_tasks" },
  ];
  expect(pendingApprovalTools(parts)).toEqual(["reschedule_task"]);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/agent-web && npm test`
Expected: FAIL（模块或导出不存在）

- [ ] **Step 3: 纯函数**

`apps/agent-web/src/approvalBatch.ts`：

```ts
/**
 * 攒批的判定，从 React 里拆出来好测。
 *
 * Eve 的审批批次必须整批一次回才结算，所以「所有待批项都有了决定」才发，
 * 并且同一批只发一次——流重放时组件会重新挂载、重新登记。
 */
export const nextDispatch = (
  pending: readonly string[],
  decisions: ReadonlyMap<string, { approved: boolean }>,
  dispatched: ReadonlySet<string>,
): { key: string; payload: { requestId: string; approved: boolean }[] } | null => {
  if (pending.length === 0) return null;
  if (!pending.every((id) => decisions.has(id))) return null;
  const key = [...pending].sort().join("|");
  if (dispatched.has(key)) return null;
  return {
    key,
    payload: pending.map((id) => ({ requestId: id, approved: decisions.get(id)!.approved })),
  };
};
```

`tools/types.ts` 追加：

```ts
/** 这条消息里还等着拍板的工具名。按消息算，确认按钮才不会挂到每条回复下面。 */
export const pendingApprovalTools = (parts: readonly unknown[]): string[] =>
  parts.flatMap((raw) => {
    const part = raw as {
      type?: string;
      toolName?: string;
      approval?: ToolCallMessagePartProps["approval"];
    };
    return part.type === "tool-call" && part.toolName && isAwaitingApproval(part.approval)
      ? [part.toolName]
      : [];
  });
```

`tools/labels.ts` 追加：

```ts
type ApprovalCopy = {
  confirm: string;
  reject: string;
  pendingYes: string;
  pendingNo: string;
  rejected: string;
};

const APPROVAL_COPY: Record<string, ApprovalCopy> = {
  create_knowledge: {
    confirm: "收录",
    reject: "先不收录",
    pendingYes: "待提交：收录",
    pendingNo: "待提交：不收录",
    rejected: "没有收录",
  },
  reschedule_task: {
    confirm: "确认改期",
    reject: "不改了",
    pendingYes: "待提交：改期",
    pendingNo: "待提交：不改期",
    rejected: "没有改期",
  },
  assign_task: {
    confirm: "确认指派",
    reject: "不指派",
    pendingYes: "待提交：指派",
    pendingNo: "待提交：不指派",
    rejected: "没有指派",
  },
  record_pregnancy_fact: {
    confirm: "确认更新",
    reject: "不更新",
    pendingYes: "待提交：更新",
    pendingNo: "待提交：不更新",
    rejected: "没有更新",
  },
};

const NEUTRAL_COPY: ApprovalCopy = {
  confirm: "确认",
  reject: "取消",
  pendingYes: "待提交：确认",
  pendingNo: "待提交：取消",
  rejected: "已取消",
};

/** 一组待确认项共用的按钮文案。混了不同工具时用中性措辞，不猜。 */
export const approvalCopy = (toolNames: readonly string[]): ApprovalCopy => {
  const unique = [...new Set(toolNames)];
  return unique.length === 1 ? (APPROVAL_COPY[unique[0]!] ?? NEUTRAL_COPY) : NEUTRAL_COPY;
};
```

同文件的 `READ_ONLY_TOOLS` 删掉 `preview_task_change`；`TOOL_TITLES` 删掉 `preview_task_change`、`update_task`、`delete_task`、`delete_record`，加上：

```ts
  complete_task: "完成待办",
  reschedule_task: "改期待办",
  undo_operation: "撤销",
```

- [ ] **Step 4: 运行确认纯函数通过**

Run: `cd apps/agent-web && npm test`
Expected: PASS

- [ ] **Step 5: 接到组件上**

`approvals.tsx`：

1. `ApprovalBatchValue` 增加：

```ts
  /** 最近一次提交失败的说明。为空表示没有失败。 */
  error: string | null;
  /** 重新提交上一次失败的那一批。 */
  retry: () => void;
```

2. Provider 内加状态 `const [error, setError] = useState<string | null>(null);` 与 `const [attempt, setAttempt] = useState(0);`。
3. 攒批 effect 改为：

```ts
  useEffect(() => {
    const next = nextDispatch([...pendingRef.current], decisions, dispatchedRef.current);
    if (!next) return;
    dispatchedRef.current.add(next.key);
    setError(null);
    setDispatching(true);
    void transport
      .respondAll(next.payload)
      .catch(() => {
        // 允许重试：不移除的话这一批永远不会再发，用户卡在一组已决定却送不出去的卡片上。
        dispatchedRef.current.delete(next.key);
        setError("没能提交，请检查网络后重试");
      })
      .finally(() => setDispatching(false));
  }, [decisions, transport, attempt]);
```

4. `retry` 为 `useCallback(() => setAttempt((n) => n + 1), [])`，并与 `error` 一起放进 `value`。
5. import `nextDispatch`。

`tools/ToolGroup.tsx` 整个替换为：

```tsx
import { useApprovalBatch } from "../approvals";
import { approvalCopy } from "./labels";

/**
 * 一条助手消息里待确认项共用的一对按钮。
 *
 * 由消息自己决定是否渲染（只在本条有待确认项时），文案按工具区分——
 * 改期就写「确认改期」，不再一律「收录」。
 */
export const ToolGroupActions = ({ toolNames }: { toolNames: string[] }) => {
  const { decideAll, dispatching, error, retry } = useApprovalBatch();
  if (toolNames.length === 0) return null;

  const copy = approvalCopy(toolNames);
  const multiple = toolNames.length > 1;

  return (
    <div className="tool-group__actions">
      {multiple ? (
        <p className="tool-group__eyebrow">以上 {toolNames.length} 项一起确认</p>
      ) : null}
      {error ? (
        <p className="tool-group__error" role="alert">
          {error}
          <button type="button" className="btn btn--link" onClick={retry}>
            重试
          </button>
        </p>
      ) : null}
      <div className="tool-group__buttons">
        <button
          type="button"
          className="btn btn--primary"
          disabled={dispatching}
          onClick={() => decideAll(true)}
        >
          {dispatching ? "正在提交…" : multiple ? `${copy.confirm}（${toolNames.length}）` : copy.confirm}
        </button>
        <button type="button" className="btn" disabled={dispatching} onClick={() => decideAll(false)}>
          {copy.reject}
        </button>
      </div>
    </div>
  );
};
```

`tools/ToolCard.tsx`：`ApprovalSlot` 里的两段文案改为 `approvalCopy([props.toolName]).pendingYes` / `.pendingNo`；`ToolStatusLine` 里 `"没有收录"` 改为 `approvalCopy([props.toolName]).rejected`。import `approvalCopy`。

`App.tsx` 的 `AssistantMessage` 改为：

```tsx
const AssistantMessage = () => {
  // 逗号拼成字符串再比较：选择器返回新数组会让组件每次都重渲染。
  const pending = useAuiState((state) =>
    pendingApprovalTools(state.message.parts).join(","),
  );
  return (
    <div className="msg msg--assistant">
      <MessagePrimitive.Parts
        components={{ Text: MarkdownText, Reasoning, tools: { Fallback: GenericToolView } }}
      />
      <ToolGroupActions toolNames={pending ? pending.split(",") : []} />
    </div>
  );
};
```

import `useAuiState` 自 `@assistant-ui/react`，`pendingApprovalTools` 自 `./tools/types`。

`styles.css` 追加：

```css
.tool-group__error { margin: 0 0 8px; font-size: 13px; color: var(--aim-danger); }
.btn--link { border: none; background: none; color: var(--aim-accent); padding: 0 0 0 8px; }
```

- [ ] **Step 6: 类型检查、测试、构建**

Run: `cd apps/agent-web && npx tsc --noEmit && npm test && npm run build`
Expected: 无错误。若 `state.message.parts` 的类型路径与本版本不符，以 `node_modules/@assistant-ui/store` 中 `AssistantState` 的定义为准调整选择器，行为不变。

- [ ] **Step 7: 手动验证**

本地栈 + `npm run dev`：
1. 连续两轮各触发一次需确认的操作（例如两次收录），第一轮确认后，**第一条回复下面不再有按钮**，只有第二条有；
2. 让 AIM 改期一项待办，按钮写「确认改期／不改了」；
3. DevTools 把网络设为 Offline 再点确认，出现「没能提交，请检查网络后重试」；恢复网络点「重试」，卡片变为已执行。

- [ ] **Step 8: 提交**

```bash
git add apps/agent-web
git commit -m "fix(web): 确认按钮只挂在有待确认项的消息上，文案按工具区分，提交失败可重试"
```

---

### Task 10：确认卡显示真实内容

**Files:**
- Modify: `apps/agent-web/src/bridge.ts`（`NativeContext` 加 `familyId` / `pregnancyId`）
- Create: `apps/agent-web/src/bizData.tsx`、`apps/agent-web/src/bizData.test.ts`
- Create: `apps/agent-web/src/tools/RescheduleTask.tsx`、`AssignTask.tsx`、`RecordFact.tsx`、`CompleteTask.tsx`
- Modify: `apps/agent-web/src/tools/index.tsx`
- Modify: `apps/agent-web/src/App.tsx`（挂 `BizDataProvider`）

**Interfaces:**
- Consumes: Task 5 的成员语义（`member_id` = `account_id`）；公开 API `GET /api/v1/pregnancies/{id}/plan`、`GET /api/v1/families/{id}`、`GET /api/v1/pregnancies/{id}`。
- Produces:
  - `NativeContext.familyId?: string`、`NativeContext.pregnancyId?: string`
  - `bizData.tsx`：`BizDataProvider`、`useBizData(): { tasks: Map<string, PlanTask>; members: Map<string, FamilyMember>; facts: Map<string, unknown>; reload: () => void }`、`memberName(m?: FamilyMember): string`、`formatWhen(iso?: string | null): string | null`

- [ ] **Step 1: 写失败测试**

`apps/agent-web/src/bizData.test.ts`：

```ts
import { expect, test } from "vitest";
import { formatWhen, memberName } from "./bizData";

test("member name prefers nickname, then role", () => {
  expect(memberName({ account_id: "1", role: "father", nickname: "老王", status: "active" })).toBe("老王");
  expect(memberName({ account_id: "1", role: "father", nickname: null, status: "active" })).toBe("爸爸");
  expect(memberName({ account_id: "1", role: "other_caregiver", nickname: " ", status: "active" })).toBe("家人");
  expect(memberName(undefined)).toBe("家人");
});

test("dates render in Chinese month/day with time", () => {
  expect(formatWhen("2026-10-09T01:00:00Z")).toMatch(/10月9日/);
  expect(formatWhen(null)).toBeNull();
  expect(formatWhen("not a date")).toBeNull();
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/agent-web && npm test`
Expected: FAIL（`./bizData` 不存在）

- [ ] **Step 3: 数据层**

`bridge.ts` 的 `NativeContext` 增加：

```ts
  /** 当前家庭与孕期。卡片凭 ID 去公开 API 取真实标题和称呼，不采信模型参数。 */
  familyId?: string;
  pregnancyId?: string;
```

`apps/agent-web/src/bizData.tsx`：

```tsx
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import type { NativeContext } from "./bridge";

export interface PlanTask {
  id: string;
  title: string;
  status: string;
  due_at: string | null;
  scheduled_for: string | null;
  assigned_member_id: string | null;
}

export interface FamilyMember {
  account_id: string;
  role: string;
  nickname: string | null;
  status: string;
}

const ROLE_NAMES: Record<string, string> = { mother: "妈妈", father: "爸爸", other_caregiver: "家人" };

export const memberName = (member: FamilyMember | undefined): string =>
  member?.nickname?.trim() || (member && ROLE_NAMES[member.role]) || "家人";

export const formatWhen = (iso: string | null | undefined): string | null => {
  if (!iso) return null;
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return null;
  return new Intl.DateTimeFormat("zh-CN", {
    month: "long",
    day: "numeric",
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Asia/Shanghai",
  }).format(parsed);
};

interface BizData {
  tasks: Map<string, PlanTask>;
  members: Map<string, FamilyMember>;
  facts: Map<string, unknown>;
  reload: () => void;
}

const EMPTY: BizData = { tasks: new Map(), members: new Map(), facts: new Map(), reload: () => {} };
const BizDataContext = createContext<BizData>(EMPTY);

const getJson = async (context: NativeContext, path: string): Promise<unknown> => {
  const response = await fetch(`${context.eveOrigin ?? ""}${path}`, {
    headers: { authorization: `Bearer ${context.token}`, accept: "application/json" },
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
};

/**
 * 卡片要显示的业务事实：待办标题与日期、家人称呼、孕期信息的当前值。
 *
 * 取不到时卡片退回显示「这项待办」之类的中性说法，不拿模型参数顶上。
 */
export const BizDataProvider = ({ context, children }: { context: NativeContext; children: ReactNode }) => {
  const [data, setData] = useState<Omit<BizData, "reload">>(EMPTY);
  const [version, setVersion] = useState(0);
  const reload = useCallback(() => setVersion((n) => n + 1), []);

  useEffect(() => {
    const { familyId, pregnancyId } = context;
    if (!familyId || !pregnancyId) return;
    let cancelled = false;
    void Promise.allSettled([
      getJson(context, `/api/v1/pregnancies/${pregnancyId}/plan`),
      getJson(context, `/api/v1/families/${familyId}`),
      getJson(context, `/api/v1/pregnancies/${pregnancyId}`),
    ]).then(([plan, family, pregnancy]) => {
      if (cancelled) return;
      setData((previous) => ({
        tasks:
          plan.status === "fulfilled"
            ? new Map(((plan.value as { tasks: PlanTask[] }).tasks ?? []).map((t) => [t.id, t]))
            : previous.tasks,
        members:
          family.status === "fulfilled"
            ? new Map(
                ((family.value as { members: FamilyMember[] }).members ?? []).map((m) => [m.account_id, m]),
              )
            : previous.members,
        facts:
          pregnancy.status === "fulfilled"
            ? new Map(
                ((pregnancy.value as { facts: { key: string; value: unknown; status: string }[] }).facts ?? [])
                  .filter((f) => f.status === "active")
                  .map((f) => [f.key, f.value]),
              )
            : previous.facts,
      }));
    });
    return () => {
      cancelled = true;
    };
  }, [context.familyId, context.pregnancyId, context.token, context.eveOrigin, version]);

  const value = useMemo(() => ({ ...data, reload }), [data, reload]);
  return <BizDataContext.Provider value={value}>{children}</BizDataContext.Provider>;
};

export const useBizData = (): BizData => useContext(BizDataContext);

/**
 * 卡片找不到自己的待办时请求一次刷新（模型可能刚新建了它）。
 * 每个 id 只请求一次，避免真不存在时反复刷。
 */
const requested = new Set<string>();
export const useEnsureTask = (taskId: string | undefined): PlanTask | undefined => {
  const { tasks, reload } = useBizData();
  const task = taskId ? tasks.get(taskId) : undefined;
  useEffect(() => {
    if (!taskId || task || requested.has(taskId)) return;
    requested.add(taskId);
    reload();
  }, [taskId, task, reload]);
  return task;
};
```

注意：原生外壳里 `eveOrigin` 为空，`/api/v1/*` 与页面同源（网关分流），开发时 Vite 已代理 `/api`（`bridge.ts` 的 dev 登录就走它）。

- [ ] **Step 4: 卡片**

`apps/agent-web/src/tools/RescheduleTask.tsx`：

```tsx
import { makeAssistantToolUI } from "@assistant-ui/react";
import { formatWhen, useEnsureTask } from "../bizData";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import { isAwaitingApproval, type ToolRenderProps } from "./types";

type Args = { taskId?: string; kind?: "schedule" | "delay"; at?: string };

export const RescheduleTaskUI = makeAssistantToolUI({
  toolName: "reschedule_task",
  render: (props: ToolRenderProps<Args>) => {
    const args = props.args ?? {};
    const task = useEnsureTask(args.taskId);
    const before = formatWhen(task?.scheduled_for ?? task?.due_at);
    const after = formatWhen(args.at);
    const verb = args.kind === "schedule" ? "安排在" : "截止改到";
    return (
      <ToolCard>
        <p className="tool-card__eyebrow">{isAwaitingApproval(props.approval) ? "将改期" : "改期"}</p>
        <h3 className="tool-card__title">{task?.title ?? "这项待办"}</h3>
        <p className="tool-card__text">
          {before ? <span className="tool-card__was">{before}</span> : null}
          {before ? " → " : ""}
          {verb} {after ?? "（时间无效）"}
        </p>
        <ApprovalSlot props={props} />
        <ToolStatusLine props={props} />
      </ToolCard>
    );
  },
});
```

`apps/agent-web/src/tools/AssignTask.tsx`：

```tsx
import { makeAssistantToolUI } from "@assistant-ui/react";
import { memberName, useBizData, useEnsureTask } from "../bizData";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import { isAwaitingApproval, type ToolRenderProps } from "./types";

type Args = { taskId?: string; assignedMemberId?: string | null };

export const AssignTaskUI = makeAssistantToolUI({
  toolName: "assign_task",
  render: (props: ToolRenderProps<Args>) => {
    const args = props.args ?? {};
    const task = useEnsureTask(args.taskId);
    const { members } = useBizData();
    const target =
      args.assignedMemberId === null
        ? "不指定负责人"
        : `交给${memberName(args.assignedMemberId ? members.get(args.assignedMemberId) : undefined)}`;
    return (
      <ToolCard>
        <p className="tool-card__eyebrow">{isAwaitingApproval(props.approval) ? "将指派" : "指派"}</p>
        <h3 className="tool-card__title">{task?.title ?? "这项待办"}</h3>
        <p className="tool-card__text">{target}</p>
        <ApprovalSlot props={props} />
        <ToolStatusLine props={props} />
      </ToolCard>
    );
  },
});
```

`apps/agent-web/src/tools/RecordFact.tsx`：

```tsx
import { makeAssistantToolUI } from "@assistant-ui/react";
import { useBizData } from "../bizData";
import { ApprovalSlot, ToolCard, ToolStatusLine } from "./ToolCard";
import { isAwaitingApproval, type ToolRenderProps } from "./types";

type Args = { key?: string; value?: unknown };

const show = (value: unknown): string =>
  typeof value === "string" ? value : value === undefined ? "（空）" : JSON.stringify(value);

export const RecordFactUI = makeAssistantToolUI({
  toolName: "record_pregnancy_fact",
  render: (props: ToolRenderProps<Args>) => {
    const args = props.args ?? {};
    const { facts } = useBizData();
    const previous = args.key ? facts.get(args.key) : undefined;
    return (
      <ToolCard>
        <p className="tool-card__eyebrow">
          {isAwaitingApproval(props.approval) ? "将更新孕期信息" : "孕期信息"}
        </p>
        <h3 className="tool-card__title">{args.key ?? "孕期信息"}</h3>
        <p className="tool-card__text">
          {previous !== undefined ? `${show(previous)} → ` : ""}
          {show(args.value)}
        </p>
        <p className="tool-card__disclaimer">孕期信息更新后不能撤销，确认前请核对。</p>
        <ApprovalSlot props={props} />
        <ToolStatusLine props={props} />
      </ToolCard>
    );
  },
});
```

`apps/agent-web/src/tools/CompleteTask.tsx`（直接执行，没有确认；显示结果，用结果里服务端给的标题）：

```tsx
import { makeAssistantToolUI } from "@assistant-ui/react";
import { ToolCard, ToolStatusLine } from "./ToolCard";
import type { ToolRenderProps } from "./types";

type Result = { data?: { title?: string } };

export const CompleteTaskUI = makeAssistantToolUI({
  toolName: "complete_task",
  render: (props: ToolRenderProps<{ taskId?: string }>) => {
    const title = (props.result as Result | undefined)?.data?.title;
    return (
      <ToolCard>
        <p className="tool-card__eyebrow">完成待办</p>
        <h3 className="tool-card__title">{title ?? "这项待办"}</h3>
        <ToolStatusLine props={props} />
      </ToolCard>
    );
  },
});
```

`tools/index.tsx` 的 `ToolRenderers` 加上 `<RescheduleTaskUI />`、`<AssignTaskUI />`、`<RecordFactUI />`、`<CompleteTaskUI />` 及对应 import。

`App.tsx`：`Conversation` 里把 `<ApprovalBridge …>` 的子树包进 `<BizDataProvider context={context}> … </BizDataProvider>`（放在 `AssistantRuntimeProvider` 内、`ApprovalBridge` 外）。

`styles.css` 追加：

```css
.tool-card__was { color: var(--aim-text-tertiary); text-decoration: line-through; }
```

- [ ] **Step 5: 测试、类型检查、构建**

Run: `cd apps/agent-web && npm test && npx tsc --noEmit && npm run build`
Expected: PASS

- [ ] **Step 6: 手动验证**

浏览器开发时 `NativeContext` 由 dev 回退生成，没有 `familyId` / `pregnancyId`。在 `bridge.ts` 的 `devFallbackContext` 里用登录响应补上：

```ts
  const { token, family_id, pregnancy_id } = (await response.json()) as {
    token: string;
    family_id?: string;
    pregnancy_id?: string | null;
  };
  return { token, theme: "light", familyId: family_id, pregnancyId: pregnancy_id ?? undefined };
```

然后：
1. 「把预约 NT 检查推到下周五上午九点」→ 卡片标题是该待办的**真实标题**，显示原日期划线 → 新日期；
2. 「让孩子爸爸去买待产包」（家里需先有已加入的爸爸）→ 卡片写「交给爸爸」或其称呼；
3. 「产检做完了」→ 直接出「完成待办 · 标题 · 已完成待办：…」，没有确认按钮。

- [ ] **Step 7: 提交**

```bash
git add apps/agent-web
git commit -m "feat(web): 改期、指派、孕期信息、完成待办各有卡片，标题与称呼取自业务数据"
```

---

### Task 11：入口模式、上下文标签、自动发送、标签页同步

**Files:**
- Create: `apps/agent-web/src/entry.ts`、`apps/agent-web/src/entry.test.ts`
- Create: `apps/agent-web/src/thread/ContextChip.tsx`
- Modify: `apps/agent-web/src/bridge.ts`
- Modify: `apps/agent-web/src/App.tsx`
- Modify: `apps/agent-web/src/styles.css`

**Interfaces:**
- Consumes: Task 10 的 `NativeContext` 扩展。
- Produces:
  - `bridge.ts`：`PageContext = { title: string; summary: string }`；`AgentEntry = { mode: "resume" } | { mode: "new"; pageContext?: PageContext; autoSend?: string }`；`NativeContext.entry?: AgentEntry`；`window.__aimOnAppear__?: () => void`
  - `entry.ts`：`resolveEntry(context: NativeContext): AgentEntry`；`withPageContext(input: SendTurnPayload, page: PageContext | null): SendTurnPayload`
  - iOS（Task 13）调用 `window.__aimOnAppear__?.()`

- [ ] **Step 1: 写失败测试**

`apps/agent-web/src/entry.test.ts`：

```ts
import { expect, test } from "vitest";
import { resolveEntry, withPageContext } from "./entry";

const base = { token: "t", theme: "light" as const };

test("missing or malformed entry means resume", () => {
  expect(resolveEntry(base)).toEqual({ mode: "resume" });
  expect(resolveEntry({ ...base, entry: { mode: "weird" } as never })).toEqual({ mode: "resume" });
});

test("new entry keeps page context and auto-send text", () => {
  const entry = {
    mode: "new" as const,
    pageContext: { title: "番茄炒蛋", summary: "菜谱" },
    autoSend: "帮我看看",
  };
  expect(resolveEntry({ ...base, entry })).toEqual(entry);
});

test("blank auto-send is dropped", () => {
  expect(resolveEntry({ ...base, entry: { mode: "new", autoSend: "  " } })).toEqual({ mode: "new" });
});

test("page context rides along as clientContext", () => {
  const input = { message: "能吃吗" } as never;
  expect(withPageContext(input, { title: "番茄炒蛋", summary: "菜谱" })).toEqual({
    message: "能吃吗",
    clientContext: { page: { title: "番茄炒蛋", summary: "菜谱" } },
  });
  expect(withPageContext(input, null)).toBe(input);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/agent-web && npm test`
Expected: FAIL

- [ ] **Step 3: 类型与纯函数**

`bridge.ts` 增加类型，并在 `NativeContext` 里加 `entry?: AgentEntry;`、在 `Window` 里加 `__aimOnAppear__?: () => void;`：

```ts
export interface PageContext {
  title: string;
  summary: string;
}

/**
 * 这次对话面是从哪里打开的。
 *
 * - resume：AIM 标签页，接回上一段。
 * - new：快捷入口，开一段新的；带 pageContext 时输入框上方显示「正在看：…」，
 *   带 autoSend 时打开就把这句话发出去（「让 Agent 分析当前记录」）。
 */
export type AgentEntry =
  | { mode: "resume" }
  | { mode: "new"; pageContext?: PageContext; autoSend?: string };
```

`apps/agent-web/src/entry.ts`：

```ts
import type { AgentEntry, NativeContext, PageContext } from "./bridge";

/** 原生传来的东西不当可信输入：认不出来就当作 resume。 */
export const resolveEntry = (context: NativeContext): AgentEntry => {
  const raw = context.entry as Partial<{ mode: string; pageContext: PageContext; autoSend: string }> | undefined;
  if (!raw || raw.mode !== "new") return { mode: "resume" };
  const entry: AgentEntry = { mode: "new" };
  if (raw.pageContext && typeof raw.pageContext.title === "string") {
    entry.pageContext = {
      title: raw.pageContext.title,
      summary: typeof raw.pageContext.summary === "string" ? raw.pageContext.summary : "",
    };
  }
  if (typeof raw.autoSend === "string" && raw.autoSend.trim()) entry.autoSend = raw.autoSend;
  return entry;
};

/**
 * 标签存在期间每一轮都附上页面上下文。
 *
 * 用 Eve 的 clientContext：只进这一轮的模型调用、不写历史，所以气泡里不会出现，
 * 也不用在消息里藏标记。
 */
export const withPageContext = <T extends object>(input: T, page: PageContext | null): T =>
  page ? { ...input, clientContext: { page } } : input;
```

- [ ] **Step 4: 运行确认通过**

Run: `cd apps/agent-web && npm test`
Expected: PASS

- [ ] **Step 5: 上下文标签组件**

`apps/agent-web/src/thread/ContextChip.tsx`：

```tsx
import type { PageContext } from "../bridge";

/** 输入框上方的「正在看：…」。点 ✕ 之后这段对话不再附带页面内容。 */
export const ContextChip = ({ page, onClear }: { page: PageContext; onClear: () => void }) => (
  <div className="context-chip" role="status">
    <span className="context-chip__label">正在看：{page.title}</span>
    <button type="button" className="context-chip__clear" aria-label="去掉页面上下文" onClick={onClear}>
      ✕
    </button>
  </div>
);
```

`styles.css` 追加：

```css
.context-chip {
  display: inline-flex; align-items: center; gap: 6px; margin: 0 12px 6px;
  padding: 4px 10px; border-radius: 999px; font-size: 13px;
  background: var(--aim-accent-soft); color: var(--aim-accent);
}
.context-chip__clear { border: none; background: none; color: inherit; font-size: 12px; padding: 0 2px; }
```

- [ ] **Step 6: 接到 App**

`App.tsx`：

1. `App` 里在 `context` 之后计算 `const entry = useMemo(() => (context ? resolveEntry(context) : null), [context]);`。
2. 恢复上一段的 effect，开头加：

```ts
    if (!context || entry?.mode !== "resume") return;
```

依赖数组改为 `[context, entry?.mode]`。

3. `Conversation` 增加 props `entry: AgentEntry` 与 `onAppearSwitch: () => void`；内部：

```tsx
  const [page, setPage] = useState<PageContext | null>(
    entry.mode === "new" ? (entry.pageContext ?? null) : null,
  );
  const pageRef = useRef(page);
  pageRef.current = page;

  const runtime = useEveAgentRuntime({
    ...(restored ? { initialSession: restored.session, initialEvents: restored.events as never } : {}),
    ...(context.eveOrigin ? { host: context.eveOrigin } : {}),
    headers: () => ({ authorization: `Bearer ${context.token}` }),
    // 用 ref 读：prepareSend 在运行时创建时就被捕获，直接读 state 会一直是初值。
    prepareSend: (input) => withPageContext(input, pageRef.current),
  });

  // 「让 Agent 分析当前记录」：打开就把问题发出去。只发一次——
  // 票据轮换等原因重渲染时不能再发。
  const autoSentRef = useRef(false);
  useEffect(() => {
    if (entry.mode !== "new" || !entry.autoSend || autoSentRef.current || restored) return;
    autoSentRef.current = true;
    void runtime.thread.append({ role: "user", content: [{ type: "text", text: entry.autoSend }] });
  }, [entry, runtime, restored]);
```

4. `Thread` 组件增加可选 props `chip?: ReactNode`，渲染在 `<ComposerPrimitive.Root>` 之前；`Conversation` 传入 `chip={page ? <ContextChip page={page} onClear={() => setPage(null)} /> : undefined}`。
5. 标签页同步：`Conversation` 内注册：

```tsx
  useEffect(() => {
    if (entry.mode !== "resume") return;
    window.__aimOnAppear__ = () => {
      const state = runtime.thread.getState();
      // 正在生成、或者用户已经在输入框里写了东西，就不要把人拽走。
      if (state.isRunning || runtime.thread.composer.getState().text.trim()) return;
      onAppearSwitch();
    };
    return () => {
      delete window.__aimOnAppear__;
    };
  }, [entry.mode, runtime, onAppearSwitch]);
```

6. `App` 里实现 `onAppearSwitch`：

```ts
  /** 从快捷入口回到标签页时，切到最近那段（快捷入口会把它存成最近一段）。 */
  const followLatestStored = useCallback(() => {
    if (!context) return;
    const stored = loadSession(accountKeyFromToken(context.token));
    if (!stored || stored.sessionId === restored?.session.sessionId) return;
    switchToSession({ id: "", eveSessionId: stored.sessionId } as AgentSessionSummary);
  }, [context, restored?.session.sessionId]);
```

`switchToSession` 里 `touchSession(context.token, picked.id, …)` 在 `picked.id` 为空串时跳过：改为 `if (picked.id) void touchSession(…)`。

7. 渲染 `Conversation` 时传 `entry={entry!}`、`onAppearSwitch={followLatestStored}`。
8. import：`useCallback`、`useMemo`、`AgentEntry`、`PageContext`、`resolveEntry`、`withPageContext`、`ContextChip`。

- [ ] **Step 7: 类型检查、测试、构建**

Run: `cd apps/agent-web && npx tsc --noEmit && npm test && npm run build`
Expected: PASS。若 `prepareSend` 不在 `useEveAgentRuntime` 的参数类型里，确认 `@assistant-ui/eve` 把其余参数透传给 `useEveAgent`（`dist/useEveAgentRuntime.js` 中 `...agentOptions`），必要时 `as Parameters<typeof useEveAgentRuntime>[0]`。

- [ ] **Step 8: 手动验证（浏览器模拟入口）**

在 DevTools 控制台先写入注入值再刷新（dev 回退只在没有 `__AIM_NATIVE__` 时生效，这里手动模拟原生）：

```js
localStorage.clear();
```

改 `bridge.ts` 的 `devFallbackContext` 返回值临时加 `entry: { mode: "new", pageContext: { title: "番茄炒蛋", summary: "菜谱：番茄、鸡蛋；步骤 3 步" } }`，刷新：
1. 输入框上方出现「正在看：番茄炒蛋 ✕」；
2. 问「这道能吃吗」，回答针对番茄炒蛋；再问「要注意什么」，仍然针对它；
3. 点 ✕ 后再问「这道菜呢」，模型不再知道是哪道；
4. 把临时值换成 `entry: { mode: "new", autoSend: "请帮我理解这条孕期记录" }`，刷新后自动发出这句话，且只发一次。

验证完**撤掉临时改动**。

- [ ] **Step 9: 提交**

```bash
git add apps/agent-web
git commit -m "feat(web): 快捷入口开新对话并带页面上下文标签，分析记录可自动发送"
```

---

### Task 12：写入后通知原生，卡片可跳回原生页面

**Files:**
- Create: `apps/agent-web/src/turnWrites.ts`、`apps/agent-web/src/turnWrites.test.ts`
- Modify: `apps/agent-web/src/bridge.ts`（`notifyTurnFinished(kinds)`）
- Modify: `apps/agent-web/src/App.tsx`（`TurnFinishedBridge`）
- Modify: `apps/agent-web/src/tools/CreateTask.tsx`、`CreateKnowledge.tsx`
- Create: `apps/agent-web/src/tools/CreateRecord.tsx`、`apps/agent-web/src/tools/OpenNative.tsx`
- Modify: `apps/agent-web/src/tools/index.tsx`

**Interfaces:**
- Produces:
  - `turnWrites.ts`：`type WriteKind = "task" | "record" | "knowledge"`；`WRITE_KINDS: Record<string, WriteKind>`；`scanTurnWrites(events: readonly unknown[], state: { kinds: Set<WriteKind> }): WriteKind[][]`——扫描新事件，每遇到一次轮次结束且本轮有写入就产出一组类别
  - `bridge.ts`：`notifyTurnFinished(kinds: WriteKind[]): void`，消息体 `{ kinds }`
  - `OpenNative` 组件：`<OpenNative kind="task" id={…} />`

- [ ] **Step 1: 写失败测试**

`apps/agent-web/src/turnWrites.test.ts`：

```ts
import { expect, test } from "vitest";
import { scanTurnWrites, type WriteKind } from "./turnWrites";

const result = (toolName: string, status = "completed") => ({
  type: "action.result",
  data: { status: "completed", result: { kind: "tool-result", toolName, callId: "c", output: { status } } },
});
const end = { type: "session.waiting", data: {} };

test("a turn that wrote a task and a record reports both kinds once", () => {
  const state = { kinds: new Set<WriteKind>() };
  const out = scanTurnWrites([result("create_task"), result("list_tasks"), result("create_record"), end], state);
  expect(out).toEqual([["task", "record"]]);
  expect(state.kinds.size).toBe(0);
});

test("read-only turns report nothing", () => {
  expect(scanTurnWrites([result("list_tasks"), end], { kinds: new Set() })).toEqual([]);
});

test("approval_required results are not writes", () => {
  expect(
    scanTurnWrites([result("reschedule_task", "approval_required"), end], { kinds: new Set() }),
  ).toEqual([]);
});

test("kinds accumulate across batches until the turn ends", () => {
  const state = { kinds: new Set<WriteKind>() };
  expect(scanTurnWrites([result("complete_task")], state)).toEqual([]);
  expect(scanTurnWrites([result("create_knowledge"), { type: "turn.completed" }], state)).toEqual([
    ["task", "knowledge"],
  ]);
});

test("undo touches everything it might have reverted", () => {
  expect(scanTurnWrites([result("undo_operation"), end], { kinds: new Set() })).toEqual([
    ["task", "record", "knowledge"],
  ]);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/agent-web && npm test`
Expected: FAIL

- [ ] **Step 3: 实现归纳**

`apps/agent-web/src/turnWrites.ts`：

```ts
export type WriteKind = "task" | "record" | "knowledge";

/** 写工具影响到的原生页面。只读工具不在表里。 */
export const WRITE_KINDS: Record<string, WriteKind[]> = {
  create_task: ["task"],
  complete_task: ["task"],
  reschedule_task: ["task"],
  assign_task: ["task"],
  create_record: ["record"],
  create_knowledge: ["knowledge"],
  record_pregnancy_fact: ["task"],
  // 撤销可能落在任何一类上；多刷一下比漏刷便宜。
  undo_operation: ["task", "record", "knowledge"],
};

const TURN_END = new Set(["turn.completed", "session.waiting", "turn.failed", "turn.cancelled"]);

type StreamEvent = {
  type?: string;
  data?: { result?: { kind?: string; toolName?: string; output?: { status?: string } } };
};

/**
 * 扫一批新到的事件：成功完成的写工具记进本轮，轮次结束时产出并清空。
 *
 * 只认 output.status === "completed"：approval_required 是「等确认」，还没写。
 */
export const scanTurnWrites = (
  events: readonly unknown[],
  state: { kinds: Set<WriteKind> },
): WriteKind[][] => {
  const finished: WriteKind[][] = [];
  for (const raw of events) {
    const event = raw as StreamEvent;
    if (event.type === "action.result") {
      const result = event.data?.result;
      const kinds = result?.toolName ? WRITE_KINDS[result.toolName] : undefined;
      if (result?.kind === "tool-result" && kinds && result.output?.status === "completed") {
        for (const kind of kinds) state.kinds.add(kind);
      }
    } else if (event.type && TURN_END.has(event.type) && state.kinds.size > 0) {
      finished.push([...state.kinds]);
      state.kinds.clear();
    }
  }
  return finished;
};
```

- [ ] **Step 4: 运行确认通过**

Run: `cd apps/agent-web && npm test`
Expected: PASS

- [ ] **Step 5: 桥与监听组件**

`bridge.ts` 的 `notifyTurnFinished` 改为：

```ts
/** 告诉原生这一轮写了哪几类东西，原生据此只刷新受影响的页面。 */
export const notifyTurnFinished = (kinds: readonly WriteKind[]): void => {
  window.webkit?.messageHandlers?.aimTurnFinished?.postMessage({ kinds });
};
```

（import `type WriteKind` 自 `./turnWrites`。）

`App.tsx` 增加组件并挂在 `Conversation` 里（`ApprovalBridge` 内部任意位置）：

```tsx
/**
 * AIM 写过东西之后让原生刷新。
 *
 * 从挂载那一刻的事件数开始扫：接回历史对话时重放的旧事件不算新写入。
 */
const TurnFinishedBridge = ({ onWrites }: { onWrites: () => void }) => {
  const events = useEveEvents();
  const seenRef = useRef<number | null>(null);
  const stateRef = useRef({ kinds: new Set<WriteKind>() });
  useEffect(() => {
    if (seenRef.current === null) {
      seenRef.current = events.length;
      return;
    }
    const fresh = events.slice(seenRef.current);
    seenRef.current = events.length;
    for (const kinds of scanTurnWrites(fresh, stateRef.current)) {
      notifyTurnFinished(kinds);
      onWrites();
    }
  }, [events, onWrites]);
  return null;
};
```

`Conversation` 里 `<TurnFinishedBridge onWrites={reload} />`，`reload` 取自 `useBizData()`——所以它要放在 `BizDataProvider` 里面。为此把 `TurnFinishedBridge` 挂在 `BizDataProvider` 的子树内，并在它里面自己 `const { reload } = useBizData();`，props 去掉 `onWrites`：

```tsx
const TurnFinishedBridge = () => {
  const { reload } = useBizData();
  // …同上，onWrites() 换成 reload()
};
```

- [ ] **Step 6: 「查看」按钮**

`apps/agent-web/src/tools/OpenNative.tsx`：

```tsx
import { hasNativeShell, openNative } from "../bridge";

/** 已执行的卡片上跳回原生详情页。浏览器开发时没有原生外壳，不显示。 */
export const OpenNative = ({ kind, id }: { kind: "task" | "record" | "knowledge"; id?: string }) =>
  id && hasNativeShell() ? (
    <button type="button" className="btn btn--link" onClick={() => openNative({ kind, id })}>
      查看
    </button>
  ) : null;
```

`CreateTask.tsx`：
- `TaskArgs` 里 `detail?: string` 改为 `description?: string`，渲染处 `args.detail` 改 `args.description`（工具参数本来就叫 `description`，原来读错了字段，描述永远显示不出来）；
- 在 `<ToolStatusLine props={props} />` 之后加：

```tsx
        <OpenNative kind="task" id={(props.result as { data?: { task_id?: string } } | undefined)?.data?.task_id} />
```

`CreateKnowledge.tsx` 同位置加：

```tsx
        <OpenNative kind="knowledge" id={(props.result as { data?: { record_id?: string } } | undefined)?.data?.record_id} />
```

`apps/agent-web/src/tools/CreateRecord.tsx`：

```tsx
import { makeAssistantToolUI } from "@assistant-ui/react";
import { OpenNative } from "./OpenNative";
import { ToolCard, ToolStatusLine } from "./ToolCard";
import type { ToolRenderProps } from "./types";

type Args = {
  recordType?: "symptom" | "checkup" | "note";
  title?: string;
  content?: string;
  symptoms?: string[];
  severity?: number;
  hospital?: string;
};

const TYPE_NAMES = { symptom: "身体感受", checkup: "产检", note: "备忘" } as const;

const summary = (args: Args): string | null => {
  if (args.recordType === "symptom" && args.symptoms?.length) {
    return `${args.symptoms.join("、")}${args.severity ? ` · 程度 ${args.severity}/5` : ""}`;
  }
  if (args.recordType === "checkup") return args.hospital ?? null;
  return args.content ?? null;
};

export const CreateRecordUI = makeAssistantToolUI({
  toolName: "create_record",
  render: (props: ToolRenderProps<Args>) => {
    const args = props.args ?? {};
    const text = summary(args);
    return (
      <ToolCard>
        <p className="tool-card__eyebrow">{TYPE_NAMES[args.recordType ?? "note"]}</p>
        <h3 className="tool-card__title">{args.title ?? TYPE_NAMES[args.recordType ?? "note"]}</h3>
        {text ? <p className="tool-card__text">{text}</p> : null}
        <ToolStatusLine props={props} />
        <OpenNative kind="record" id={(props.result as { data?: { record_id?: string } } | undefined)?.data?.record_id} />
      </ToolCard>
    );
  },
});
```

`tools/index.tsx` 加 `<CreateRecordUI />`。

- [ ] **Step 7: 类型检查、测试、构建**

Run: `cd apps/agent-web && npx tsc --noEmit && npm test && npm run build`
Expected: PASS

- [ ] **Step 8: 手动验证（浏览器）**

在控制台模拟原生消息通道后发一句会写入的话：

```js
window.webkit = { messageHandlers: { aimTurnFinished: { postMessage: (b) => console.log("turn", b) } } };
```

1. 「提醒我明天下午去拿报告」→ 控制台打印 `turn { kinds: ["task"] }`，只打印一次；
2. 刷新页面接回这段对话 → 控制台**不**再打印（重放不算新写入）；
3. 「今天有点头晕，程度 2」→ 出现「身体感受」卡片，打印 `turn { kinds: ["record"] }`。

- [ ] **Step 9: 提交**

```bash
git add apps/agent-web
git commit -m "feat(web): AIM 写入后按类别通知原生刷新，已创建卡片可跳回原生详情"
```

---

### Task 13：iOS 注入入口、处理跳转、按通知刷新

**Files:**
- Modify: `apps/ios/AimApp/Features/Agent/AgentWebView.swift`
- Modify: `apps/ios/AimApp/Features/Agent/AgentView.swift`
- Modify: `apps/ios/AimApp/Features/Agent/AgentStore.swift`
- Modify: `apps/ios/AimApp/App/AimApp.swift`
- Modify: `apps/ios/AimApp/Features/Home/HomeView.swift`
- Modify: `apps/ios/AimApp/Features/Records/RecordDetailView.swift`
- Test: `apps/ios/AimApp/Tests/AgentStoreTests.swift`

**Interfaces:**
- Consumes: Task 11 的 `entry` 结构、`__aimOnAppear__`；Task 12 的 `{ kinds }` 消息体；Task 10 的 `familyId` / `pregnancyId`。
- Produces:
  - `enum AgentWebEntry: Equatable { case resume; case new(pageContext: AgentContext?, autoSend: String?) }`，`var jsonObject: [String: Any]`
  - `AgentWebView.contextPayload(environment:colorScheme:entry:) -> String`（internal static，供测试）
  - `AgentWebView.onTurnFinished: ([String]) -> Void`
  - `AgentStore.pendingAutoSend: String?`、`AgentStore.prepareAnalysis(_ text: String, context: AgentContext)`
  - `@Observable final class AgentDestinations`（放在 `AgentView.swift`）
  - `Notification.Name.aimAgentTurnFinished` 的 `userInfo["kinds"]: [String]`

- [ ] **Step 1: 写失败测试**

`AgentStoreTests.swift` 末尾（类内）追加：

```swift
    func testQuickEntryPayloadCarriesPageContextAndScope() throws {
        let family = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let pregnancy = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let environment = APIEnvironment(
            baseURL: URL(string: "http://127.0.0.1:8100")!,
            eveBaseURL: URL(string: "http://127.0.0.1:2210")!,
            bearerToken: "aim.v1.\"quoted\"",
            accountID: nil,
            familyID: family,
            pregnancyID: pregnancy
        )
        let payload = AgentWebView.contextPayload(
            environment: environment,
            colorScheme: .dark,
            entry: .new(pageContext: AgentContext(title: "番茄炒蛋", summary: "菜谱"), autoSend: nil)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["token"] as? String, "aim.v1.\"quoted\"")
        XCTAssertEqual(object["theme"] as? String, "dark")
        XCTAssertEqual(object["familyId"] as? String, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(object["pregnancyId"] as? String, "33333333-3333-3333-3333-333333333333")
        let entry = try XCTUnwrap(object["entry"] as? [String: Any])
        XCTAssertEqual(entry["mode"] as? String, "new")
        XCTAssertEqual((entry["pageContext"] as? [String: String])?["title"], "番茄炒蛋")
        XCTAssertNil(entry["autoSend"])
    }

    func testTabEntryResumes() throws {
        let environment = APIEnvironment(
            baseURL: URL(string: "http://127.0.0.1:8100")!,
            eveBaseURL: URL(string: "http://127.0.0.1:2210")!,
            bearerToken: nil, accountID: nil, familyID: nil, pregnancyID: nil
        )
        let payload = AgentWebView.contextPayload(environment: environment, colorScheme: .light, entry: .resume)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        XCTAssertEqual((object["entry"] as? [String: String])?["mode"], "resume")
        XCTAssertNil(object["familyId"])
    }

    func testAnalysisPreparesAnAutoSendInsteadOfCallingEve() {
        let store = AgentStore()
        store.prepareAnalysis("请帮我理解这条记录", context: AgentContext(title: "记录", summary: "症状：头晕"))
        XCTAssertEqual(store.pendingAutoSend, "请帮我理解这条记录")
        XCTAssertEqual(store.context?.title, "记录")
        XCTAssertTrue(store.messages.isEmpty)
    }
```

（`APIEnvironment` 的成员逐一初始化器参数顺序以 `Core/Networking/APIEnvironment.swift` 的属性声明为准：`baseURL, eveBaseURL, bearerToken, accountID, familyID, pregnancyID`。）

- [ ] **Step 2: 运行确认失败**

Run: `make ios-test`
Expected: 编译失败（`contextPayload(environment:…)`、`prepareAnalysis` 不存在）

- [ ] **Step 3: `AgentWebView.swift`**

1. 文件顶部（`AgentWebRoute` 之后）加：

```swift
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
```

2. `AgentWebView` 加属性 `let entry: AgentWebEntry`，`onTurnFinished` 类型改为 `([String]) -> Void`，`Coordinator` 同步改类型。
3. 替换两个静态函数：

```swift
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
        if let familyID = environment.familyID { object["familyId"] = familyID.uuidString.lowercased() }
        if let pregnancyID = environment.pregnancyID {
            object["pregnancyId"] = pregnancyID.uuidString.lowercased()
        }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func contextScript(_ payload: String) -> String {
        // 在 documentStart 注入：页面的 loadNativeContext 一跑就要能读到。
        "window.__AIM_NATIVE__ = \(payload);"
    }
```

4. `makeUIView` 里 `WKUserScript(source: Self.contextScript(Self.contextPayload(environment: environment, colorScheme: colorScheme, entry: entry)), …)`；`updateUIView` 里 `let payload = Self.contextPayload(environment: environment, colorScheme: colorScheme, entry: entry)`。
5. `Coordinator.userContentController` 的 `aimTurnFinished` 分支：

```swift
            case "aimTurnFinished":
                let kinds = (message.body as? [String: Any])?["kinds"] as? [String] ?? []
                onTurnFinished(kinds)
```

- [ ] **Step 4: `AgentStore.swift`**

在 `focus(context:)` 之后加，并**删除** `ask(_:context:environment:)`：

```swift
    /// 下一次从快捷入口打开对话面时要自动发出的话。对话面出现后清空。
    var pendingAutoSend: String?

    /// 「让 Agent 分析当前记录」：带着这条记录开一段新对话，并把问题直接发出去。
    /// 由网页端发送——原来在这里调 Eve，结果是后台跑了一段用户看不见的对话。
    func prepareAnalysis(_ text: String, context: AgentContext) {
        focus(context: context)
        pendingAutoSend = text
    }
```

- [ ] **Step 5: `AgentView.swift`**

1. 在 `extension Notification.Name` 之前加：

```swift
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
```

2. `AgentView` 增加：

```swift
    @Environment(AgentDestinations.self) private var destinations: AgentDestinations?
    @State private var entry: AgentWebEntry
    @State private var destination: AgentDestination?

    init(store: AgentStore, onClose: (() -> Void)? = nil) {
        self.store = store
        self.onClose = onClose
        // 在创建时定下入口并存进 @State：视图重建时 init 会再跑，但入口不能跟着变，
        // 否则 WebView 会拿到一个新的 entry 把对话切走。
        _entry = State(initialValue: onClose == nil
            ? .resume
            : .new(pageContext: store.context, autoSend: store.pendingAutoSend))
    }
```

3. `AgentWebView(…)` 调用处传 `entry: entry`，并改两个回调：

```swift
                    onNavigate: { route in
                        Task {
                            destination = await destinations?.resolve(route)
                        }
                    },
                    onTurnFinished: { kinds in
                        // 用通知广播而不是让对话面直接去刷别的 store：那样它就得知道
                        // 全 App 有哪些页面。
                        NotificationCenter.default.post(
                            name: .aimAgentTurnFinished, object: nil, userInfo: ["kinds": kinds]
                        )
                    },
```

4. 在 `.toolbar(.hidden, for: .navigationBar)` 之后加：

```swift
            .navigationDestination(item: $destination) { target in
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
            .onAppear {
                store.pendingAutoSend = nil
                // 标签页重新出现：若刚才在快捷入口里开了新的一段，切过去。
                if onClose == nil {
                    webView?.evaluateJavaScript("window.__aimOnAppear__?.()")
                }
            }
```

- [ ] **Step 6: `AimApp.swift`**

`MainTabView`：

1. 加 `@State private var agentDestinations: AgentDestinations?`。
2. `TabView { … }` 之后链上：

```swift
        .environment(agentDestinations)
        .onAppear {
            if agentDestinations == nil {
                agentDestinations = AgentDestinations(
                    planStore: planStore,
                    recordStore: recordStore,
                    libraryStore: libraryStore,
                    agentStore: agentStore
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aimAgentTurnFinished)) { note in
            let kinds = Set(note.userInfo?["kinds"] as? [String] ?? ["task", "record", "knowledge"])
            Task { await refresh(after: kinds) }
        }
```

3. 加方法：

```swift
    /// AIM 写过东西之后只刷新受影响的页面。首页同时显示待办和最近记录，两类都要刷它。
    private func refresh(after kinds: Set<String>) async {
        if kinds.contains("task") {
            await planStore.load()
        }
        if kinds.contains("record") {
            await recordStore.load()
        }
        if kinds.contains("task") || kinds.contains("record") {
            await timelineStore.load()
        }
        if kinds.contains("record") || kinds.contains("knowledge") {
            await libraryStore.load()
        }
    }
```

- [ ] **Step 7: 入口调用点**

`HomeView.swift`：首页右上角 AIM 按钮开的是普通新对话，不带标签：

```swift
                    onAgent: {
                        agentStore.focus(context: nil)
                        showingAgent = true
                    }
```

（若 `agentContext` 因此不再被使用，删掉这个计算属性。）

`RecordDetailView.swift` 的按钮改为：

```swift
                Button("让 Agent 分析当前记录") {
                    agentStore.prepareAnalysis(
                        analysisPrompt(for: currentRecord),
                        context: AgentContext(
                            title: "记录",
                            summary: "\(currentRecord.type.displayName)：\(currentRecord.displayTitle)"
                        )
                    )
                    showingAgent = true
                }
```

- [ ] **Step 8: 编译并运行测试**

Run: `make ios-test`
Expected: 新增三条通过；除已知两条 UI 测试失败外全部通过。若 `AgentStoreTests` 里其它引用 `ask(` 的用例编译失败，删掉那些用例（它们测的是已移除的后台发送路径）。

- [ ] **Step 9: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): 对话面按入口开新对话并带上下文，卡片可跳回原生页，AIM 写入后刷新首页与资料库"
```

---

### Task 14：端到端验证与收尾

**Files:**
- Modify: `docs/superpowers/specs/2026-09-28-aim-agent-hardening-design.md`（§3.4 的「判别联合」措辞）

- [ ] **Step 1: 规格措辞对齐实现**

§3.4 中这一句：

```
- `create_record` 按 `recordType` 拆成判别联合 schema：…
```

改为：

```
- `create_record` 的参数按类型平铺并在描述里写明各类型该填哪些：`symptom` 要求 `symptoms`（非空）与 `severity`（1–5）；`checkup` 的四个文本字段缺省为空串、指标只能取 `weight_kg` / `systolic` / `diastolic` / `fasting_glucose` / `hemoglobin`；`note` 要求 `content`。不用判别联合是因为 OpenAI 兼容的函数调用要求顶层为 object。缺字段在工具内先拦下，中文错误回到模型手里。
```

- [ ] **Step 2: 全量自动化检查**

```bash
make -C services/api test lint
cd services/agent && npm run build && npm test && npm run lint && cd -
cd apps/agent-web && npm test && npx tsc --noEmit && npm run build && cd -
make ios-test
```

Expected: 全部通过（iOS 除已知两条 UI 测试）。

- [ ] **Step 3: 模拟器端到端**

`make dev`（要验真实模型行为时在 `.env` 设 `EVE_USE_MOCK_MODEL=0` 与 `DEEPSEEK_API_KEY`），模拟器跑 App，逐项：

1. 孕期页新建一条待办「预约 NT」；到 AIM 标签说「NT 已经约好了，下周五上午九点」→ 出改期卡，标题是「预约 NT」、显示新时间，按钮「确认改期」；确认后回孕期页，**不用下拉**就看到新时间。
2. AIM 里说「预约 NT 做完了」→ 直接完成、无确认；再说「撤销刚才那个」→ 恢复未完成；孕期页自动更新。
3. 菜谱详情页点「问问 AIM」→ 新对话，输入框上方「正在看：<菜名>」；问「孕晚期能吃吗」，回答针对这道菜；关闭后切到 AIM 标签，标签页显示的是刚才那段。
4. 记录详情页点「让 Agent 分析当前记录」→ 打开即看到自动发出的问题和回答；历史列表里只多一段（不再有后台的那段）。
5. 说「帮我记一下今天有点头晕，程度 2」→ 出「身体感受」卡片，点「查看」进入原生记录详情。
6. 同一轮让它「把这三道菜收进菜谱：…」→ 三张卡，一次确认，全部入库；第一条回复下不再残留按钮。
7. 新注册一个账号、不填预产期直接进 AIM 让它建待办 → 得到中文引导「还没有建立孕期档案…」。

任何一项不符，回到对应任务修复并补测试。

- [ ] **Step 4: 提交**

```bash
git add docs/superpowers/specs/2026-09-28-aim-agent-hardening-design.md
git commit -m "docs: 规格里 create_record 的参数形态与实现对齐"
```

- [ ] **Step 5: 部署提示（不在本计划内执行）**

上线前需要：服务器 `.env` 确认有 `DEEPSEEK_API_KEY`；执行迁移 `0009`；网页产物重新构建并随网关发布；iOS 重新打包。部署步骤见 `infrastructure/deploy/README.md`。
