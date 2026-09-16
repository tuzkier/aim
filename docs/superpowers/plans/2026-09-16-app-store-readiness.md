# App Store 上架前工程准备 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补齐 App Store 审核的硬性要求：30 天缓冲的账号注销（后端 + iOS）、隐私政策与用户协议页面及注册同意、Agent 界面医疗免责声明、iOS 隐私清单 / 版本号 / 出口合规声明，以及部署文档里的上架前清单。

**Architecture:** 后端在 identity 上下文里给账号加 `pending_deletion` 状态与 `deletion_requested_at`，新增注销申请接口，登录时自动撤销，平台层认证依赖加一次账号状态查询让旧票立即失效，清理逻辑是一个应用层用例 + 命令行脚本。法律页面是两个静态 HTML，由现有 nginx 网关的 `/legal/` 路径提供，本地与生产同构。iOS 端在家庭页加「账号」分组承载四个入口，注册页加同意勾选，Agent 头部加免责声明，打包元数据直接改 pbxproj 与 Info.plist。

**Tech Stack:** FastAPI + SQLAlchemy 2 async + Alembic + pytest（`services/api`）；SwiftUI iOS 17 + XCTest/XCUITest（`apps/ios`）；nginx + docker compose（`infrastructure/`）。

规格：`docs/superpowers/specs/2026-09-16-app-store-readiness-design.md`。

## Global Constraints

- 注销采用「停用 30 天再删」：申请即 `pending_deletion`；30 天内登录自动恢复并返回 `deletion_cancelled: true`；超过 30 天按不存在处理（401，与登录失败同一文案「手机号或密码不对」）。
- 申请注销必须带密码；密码错 401，文案同登录失败。已是 `pending_deletion` 时幂等 204。
- 所有需要认证的接口在验签后检查账号状态，非 `active` 一律 401。
- 运营主体「王韩斌」、联系邮箱 `whb4d12@gmail.com`，在法律页面里各只出现于一处常量。
- 法律页面 URL 固定为 `<网关>/legal/privacy.html` 与 `<网关>/legal/terms.html`。
- `Info.plist` 的 `NSAllowsArbitraryLoads` **保留不动**（生产后端仍是裸 IP）。
- iOS：部署目标 17，相对字体，颜色只用 `Color.aim*`，间距只用 `AimMetrics`，简体中文文案；sheet 内提交失败在 sheet 内显示、提交中 loading 并禁用。
- `services/api/tests/architecture/test_dependencies.py` 的规则：`contexts/*/domain` 不得 import fastapi / pydantic / sqlalchemy，也不得 import 任何 `.adapters`。
- 提交信息沿用仓库习惯：`feat(api): …` / `feat(ios): …` / `feat(infra): …` / `test(…)` / `docs: …`，中文。
- 每个任务结束前运行该任务列出的验证命令；后端任务额外跑 `make -C services/api lint`。

## 命令速查

仓库根目录 `/Users/hanbin/Workspace/AI/aim`。

```bash
# 后端测试需要本地 PostgreSQL（compose 栈的 55434 端口）。先确认：
docker ps --format '{{.Names}} {{.Status}}' | grep aim-postgres || make dev   # make dev 会阻塞，放后台

# 后端：单个测试文件 / 全部
cd services/api && python3 -m pytest tests/integration/identity/test_login.py -q
cd services/api && python3 -m pytest -q
# 后端：契约导出（改了接口就要跑，产物在 contracts/public-api/openapi.json）
make -C services/api contracts
# 后端 lint
make -C services/api lint

# iOS 语法 / 编译 / 单元测试 / 单个 UI 测试
make ios-parse
make ios-build 2>&1 | grep -E "error:|BUILD" | tail
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests test 2>&1 | grep -E "error:|Executed|TEST"
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppUITests/CoreJourneyUITests/<测试名> test 2>&1 | grep -E "error:|passed|failed|Executed|TEST"
```

UI 测试需要本地栈（`make dev`，含 `--profile local` 的网关，端口 8080）。模拟器连本地 API `127.0.0.1:8100`，网关 `127.0.0.1:8080`。

## pbxproj 约定

`apps/ios/AimApp.xcodeproj/project.pbxproj` 手写维护。每个源文件四处条目：`PBXBuildFile`（`A2…`）、`PBXFileReference`（`A1…`）、所属 `PBXGroup` 的 children、目标 `PBXSourcesBuildPhase` 的 files（App 目标 `A30000000000000000000004`，单元测试目标 `A30000000000000000000006`）。资源文件进 `PBXResourcesBuildPhase`（App 目标 `A30000000000000000000005`）而不是 Sources。当前最大编号 `…0137`。本计划分配：

| 文件 | fileRef | buildFile | 分组 |
| --- | --- | --- | --- |
| `Features/Family/AccountSection.swift` | `A10000000000000000000138` | `A20000000000000000000138` | `A40000000000000000000007 /* Family */` |
| `Core/DesignSystem/Components/SafariView.swift` | `A10000000000000000000139` | `A20000000000000000000139` | Components 分组（含 `AimToast.swift` 的那个，`grep -n "AimToast.swift \*/,$"` 定位） |
| `Resources/PrivacyInfo.xcprivacy` | `A10000000000000000000140` | `A20000000000000000000140` | 含 `Resources/Info.plist` 的分组（`grep -n "Resources/Info.plist \*/,$"` 定位）；build phase 是 `A30000000000000000000005 /* Resources */` |
| `Tests/SessionResponseTests.swift` | `A10000000000000000000141` | `A20000000000000000000141` | `A40000000000000000000014 /* Tests */` |
| `Tests/LegalPagesTests.swift` | `A10000000000000000000142` | `A20000000000000000000142` | `A40000000000000000000014 /* Tests */` |

`PBXFileReference` 里 `.xcprivacy` 的 `lastKnownFileType = text.xml`。

---

### Task 1: 账号领域模型与迁移（`pending_deletion` + `deletion_requested_at`）

**Files:**
- Modify: `services/api/src/aim_api/contexts/identity/domain/account.py`
- Create: `services/api/migrations/versions/0008_account_deletion.py`
- Modify: `services/api/src/aim_api/contexts/family/adapters/outbound/persistence/models.py:16-25`
- Modify: `services/api/src/aim_api/contexts/family/adapters/outbound/persistence/repositories.py:32-56, 189-197`
- Create: `services/api/tests/domain/identity/test_account_deletion.py`

**Interfaces:**
- Produces（domain）：`AccountStatus.pending_deletion`；`DELETION_GRACE_PERIOD: timedelta = timedelta(days=30)`；`Account.deletion_requested_at: datetime | None`；`Account.request_deletion(now: datetime) -> None`；`Account.cancel_deletion() -> None`；`Account.deletion_is_expired(now: datetime) -> bool`；`Account.can_log_in(now: datetime) -> bool`。
- Produces（repository）：`SqlAlchemyFamilyRepository.save_account_status(account: Account) -> None`（把 `status` 与 `deletion_requested_at` 写回）。

- [ ] **Step 1: 写失败的领域测试**

先看 `services/api/tests/domain/` 下有没有 `identity` 目录；没有就建，并在里面放一个空的 `__init__.py`（与其它 domain 子目录一致；用 `ls services/api/tests/domain/family` 核对是否有 `__init__.py`，有则照做，没有则不加）。

`services/api/tests/domain/identity/test_account_deletion.py`：

```python
from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import uuid4

from aim_api.contexts.identity.domain.account import (
    DELETION_GRACE_PERIOD,
    Account,
    AccountStatus,
)

NOW = datetime(2026, 9, 16, 10, 0, tzinfo=UTC)


def _account() -> Account:
    return Account.register(uuid4(), "13800000000", password_hash="x", now=NOW)


def test_request_deletion_marks_pending_and_records_time() -> None:
    account = _account()
    account.request_deletion(now=NOW)
    assert account.status is AccountStatus.pending_deletion
    assert account.deletion_requested_at == NOW


def test_request_deletion_is_idempotent_and_keeps_first_timestamp() -> None:
    account = _account()
    account.request_deletion(now=NOW)
    account.request_deletion(now=NOW + timedelta(days=3))
    assert account.deletion_requested_at == NOW


def test_cancel_deletion_restores_active() -> None:
    account = _account()
    account.request_deletion(now=NOW)
    account.cancel_deletion()
    assert account.status is AccountStatus.active
    assert account.deletion_requested_at is None


def test_grace_period_is_thirty_days() -> None:
    assert DELETION_GRACE_PERIOD == timedelta(days=30)
    account = _account()
    account.request_deletion(now=NOW)
    assert not account.deletion_is_expired(now=NOW + timedelta(days=29, hours=23))
    assert account.deletion_is_expired(now=NOW + DELETION_GRACE_PERIOD)


def test_can_log_in_only_when_active_or_within_grace() -> None:
    active = _account()
    assert active.can_log_in(now=NOW)

    pending = _account()
    pending.request_deletion(now=NOW)
    assert pending.can_log_in(now=NOW + timedelta(days=10))
    assert not pending.can_log_in(now=NOW + timedelta(days=31))

    disabled = _account()
    disabled.status = AccountStatus.disabled
    assert not disabled.can_log_in(now=NOW)
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd services/api && python3 -m pytest tests/domain/identity/test_account_deletion.py -q 2>&1 | tail -5
```

预期：`ImportError: cannot import name 'DELETION_GRACE_PERIOD'`。

- [ ] **Step 3: 改领域模型**

`services/api/src/aim_api/contexts/identity/domain/account.py` 全文替换为：

```python
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from uuid import UUID


class AccountStatus(StrEnum):
    active = "active"
    disabled = "disabled"
    #: 用户申请了注销。缓冲期内登录即撤销；到期由清理脚本真正删除。
    pending_deletion = "pending_deletion"


#: 注销缓冲期。App Store 要求 App 内能发起注销，但不要求立即删除；
#: 留 30 天给误操作和「删了才想起来资料还在里面」。
DELETION_GRACE_PERIOD = timedelta(days=30)


def normalize_phone(phone: str) -> str:
    value = phone.strip().replace(" ", "").replace("-", "")
    if value.startswith("+86"):
        value = value[3:]
    if not re.fullmatch(r"[0-9]{6,20}", value):
        raise ValueError("phone must contain 6 to 20 digits")
    return value


@dataclass(slots=True)
class Account:
    """An account is an identity; family roles live on FamilyMember instead."""

    id: UUID
    phone: str
    #: argon2id 哈希。域模型里从不出现明文密码。
    password_hash: str = ""
    status: AccountStatus = AccountStatus.active
    created_at: datetime | None = None
    deletion_requested_at: datetime | None = None

    @classmethod
    def register(
        cls,
        account_id: UUID,
        phone: str,
        *,
        password_hash: str = "",
        now: datetime | None = None,
    ) -> Account:
        return cls(
            id=account_id,
            phone=normalize_phone(phone),
            password_hash=password_hash,
            created_at=now or datetime.now(UTC),
        )

    def ensure_active(self) -> None:
        if self.status is not AccountStatus.active:
            raise ValueError("disabled account cannot perform family operations")

    def request_deletion(self, *, now: datetime) -> None:
        # 重复申请不刷新时间：否则用户每点一次，30 天就重新起算。
        if self.status is AccountStatus.pending_deletion:
            return
        self.status = AccountStatus.pending_deletion
        self.deletion_requested_at = now

    def cancel_deletion(self) -> None:
        self.status = AccountStatus.active
        self.deletion_requested_at = None

    def deletion_is_expired(self, *, now: datetime) -> bool:
        if self.status is not AccountStatus.pending_deletion or self.deletion_requested_at is None:
            return False
        return now >= self.deletion_requested_at + DELETION_GRACE_PERIOD

    def can_log_in(self, *, now: datetime) -> bool:
        if self.status is AccountStatus.active:
            return True
        if self.status is AccountStatus.pending_deletion:
            return not self.deletion_is_expired(now=now)
        return False
```

- [ ] **Step 4: 跑领域测试确认通过**

同 Step 2 命令。预期 `5 passed`。

- [ ] **Step 5: 写迁移**

`services/api/migrations/versions/0008_account_deletion.py`：

```python
"""Let an account request its own deletion and remember when."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0008_account_deletion"
down_revision = "0007_agent_sessions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # status 本来就是 String(20)，新值 pending_deletion 直接写入即可，不需要改列。
    op.add_column(
        "accounts",
        sa.Column("deletion_requested_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("accounts", "deletion_requested_at")
```

- [ ] **Step 6: 改 ORM 模型与仓储**

`models.py` 的 `AccountModel` 在 `created_at` 之后加：

```python
    deletion_requested_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
```

`repositories.py`：`ensure_account` 里构造 `AccountModel(...)` 时加 `deletion_requested_at=account.deletion_requested_at,`；`_to_account` 加 `deletion_requested_at=model.deletion_requested_at,`；在 `get_account_by_phone` 之后新增：

```python
    async def save_account_status(self, account: Account) -> None:
        model = await self.session.get(AccountModel, account.id)
        if model is None:
            raise ValueError("account does not exist")
        model.status = account.status.value
        model.deletion_requested_at = account.deletion_requested_at
        await self.session.flush()
```

- [ ] **Step 7: 跑迁移相关的集成测试与 lint**

```bash
cd services/api && python3 -m pytest tests/integration/identity tests/integration/test_password_migration.py tests/architecture -q 2>&1 | tail -3 && make lint
```

预期全部通过（conftest 会在一次性数据库上跑到 `0008`）。

- [ ] **Step 8: 提交**

```bash
git add services/api/src/aim_api/contexts/identity/domain/account.py services/api/migrations/versions/0008_account_deletion.py services/api/src/aim_api/contexts/family/adapters/outbound/persistence services/api/tests/domain/identity
git commit -m "feat(api): 账号支持申请注销与 30 天缓冲期"
```

---

### Task 2: 注销申请接口、登录自动撤销、认证依赖检查账号状态

**Files:**
- Modify: `services/api/src/aim_api/platform/auth/context.py`
- Modify: `services/api/src/aim_api/contexts/identity/adapters/inbound/http/router.py`（`SessionResponse`、`login`、新增端点）
- Modify: `services/api/src/aim_api/contexts/family/adapters/inbound/http/router.py:131-132` 及其 `_actor(request)` 调用处
- Modify: `services/api/src/aim_api/contexts/planning/adapters/inbound/http/router.py:188-189` 及调用处
- Modify: `services/api/src/aim_api/contexts/records/adapters/inbound/http/router.py:100-101` 及调用处
- Modify: `services/api/src/aim_api/contexts/pregnancy/adapters/inbound/http/router.py:127-128` 及调用处
- Modify: `services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/sessions_router.py:65,82,143,157`
- Modify: `services/api/src/aim_api/composition/today/router.py:64`
- Modify: `services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/router.py:654`（resolve-session）
- Create: `services/api/tests/integration/identity/test_account_deletion.py`
- Regenerate: `contracts/public-api/openapi.json`

**Interfaces:**
- Consumes：Task 1 的 `Account.request_deletion / cancel_deletion / can_log_in`、`save_account_status`。
- Produces：`POST /api/v1/auth/deletion-request`（Bearer + `{"password": str}` → 204）；`SessionResponse.deletion_cancelled: bool`；`platform.auth.context.authenticate_active(request) -> ActorContext`（async）；`platform.auth.context.ensure_account_active(database, account_id) -> None`（async，非 active 抛 401）。

- [ ] **Step 1: 写失败的集成测试**

`services/api/tests/integration/identity/test_account_deletion.py`：

```python
from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text

from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings

LOGIN_FAILURE = "手机号或密码不对"
PASSWORD = "a-good-password"


def _phone() -> str:
    return "138" + str(int(uuid4()) % 10**8).zfill(8)


def _register(client: TestClient, phone: str) -> dict:
    response = client.post(
        "/api/v1/auth/register", json={"phone": phone, "password": PASSWORD, "role": "mother"}
    )
    assert response.status_code == 201, response.text
    return response.json()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _backdate_deletion(account_id: str, days: int) -> None:
    """把申请时间往前拨，模拟缓冲期流逝。测试库地址来自 conftest 设好的 DATABASE_URL。"""
    url = get_settings().database_url.replace("+asyncpg", "+psycopg", 1)
    engine = create_engine(url)
    with engine.begin() as conn:
        conn.execute(
            text("UPDATE accounts SET deletion_requested_at = :at WHERE id = :id"),
            {"at": datetime.now(UTC) - timedelta(days=days), "id": UUID(account_id)},
        )
    engine.dispose()


def test_deletion_request_needs_the_password() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        session = _register(client, _phone())
        response = client.post(
            "/api/v1/auth/deletion-request",
            json={"password": "wrong-password"},
            headers=_auth(session["token"]),
        )
        assert response.status_code == 401
        assert LOGIN_FAILURE in response.text


def test_deletion_request_invalidates_existing_tokens() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        session = _register(client, _phone())
        headers = _auth(session["token"])
        assert client.get(f"/api/v1/families/{session['family_id']}", headers=headers).status_code == 200

        response = client.post(
            "/api/v1/auth/deletion-request", json={"password": PASSWORD}, headers=headers
        )
        assert response.status_code == 204, response.text

        assert client.get(f"/api/v1/families/{session['family_id']}", headers=headers).status_code == 401
        # 幂等：再申请一次仍是 204，而不是因为票已失效而 401。
        again = client.post(
            "/api/v1/auth/deletion-request", json={"password": PASSWORD}, headers=headers
        )
        assert again.status_code == 204, again.text


def test_login_within_grace_period_cancels_deletion() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        phone = _phone()
        session = _register(client, phone)
        client.post(
            "/api/v1/auth/deletion-request",
            json={"password": PASSWORD},
            headers=_auth(session["token"]),
        )

        login = client.post("/api/v1/auth/login", json={"phone": phone, "password": PASSWORD})
        assert login.status_code == 200, login.text
        assert login.json()["deletion_cancelled"] is True

        # 恢复之后一切如常，再登录一次不再提示。
        again = client.post("/api/v1/auth/login", json={"phone": phone, "password": PASSWORD})
        assert again.json()["deletion_cancelled"] is False
        headers = _auth(again.json()["token"])
        assert client.get(f"/api/v1/families/{session['family_id']}", headers=headers).status_code == 200


def test_login_after_grace_period_looks_like_unknown_account() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        phone = _phone()
        session = _register(client, phone)
        client.post(
            "/api/v1/auth/deletion-request",
            json={"password": PASSWORD},
            headers=_auth(session["token"]),
        )
        _backdate_deletion(session["account_id"], days=31)

        login = client.post("/api/v1/auth/login", json={"phone": phone, "password": PASSWORD})
        unknown = client.post("/api/v1/auth/login", json={"phone": _phone(), "password": PASSWORD})
        assert login.status_code == unknown.status_code == 401
        assert login.json() == unknown.json()


def test_register_response_reports_no_cancellation() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        assert _register(client, _phone())["deletion_cancelled"] is False
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd services/api && python3 -m pytest tests/integration/identity/test_account_deletion.py -q 2>&1 | tail -8
```

预期：多个失败（404 / KeyError `deletion_cancelled`）。

- [ ] **Step 3: 平台层加账号状态检查**

`services/api/src/aim_api/platform/auth/context.py` 末尾追加（文件顶部 `import` 区加 `from sqlalchemy import text`）：

```python
async def ensure_account_active(database: object, account_id: UUID) -> None:
    """票是无状态签名，注销账号的旧票在 30 天内仍然验得过。

    所以验签之后再按主键查一次状态。用一句 SQL 而不是 import 家庭上下文的模型：
    platform 不该依赖某个 context 的持久化层。
    """
    async with database.session() as session:  # type: ignore[attr-defined]
        status_value = await session.scalar(
            text("SELECT status FROM accounts WHERE id = :id"), {"id": account_id}
        )
    if status_value != "active":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="account is not active"
        )


async def authenticate_active(request: Request) -> ActorContext:
    actor = authenticate(request)
    await ensure_account_active(request.app.state.database, actor.account_id)
    return actor
```

- [ ] **Step 4: 把所有认证调用换成 `authenticate_active`**

四个上下文路由（family / planning / records / pregnancy）的 `_actor`：

```python
async def _actor(request: Request) -> ActorContext:
    return await authenticate_active(request)
```

import 行从 `authenticate` 改为 `authenticate_active`（`ActorContext` 保留）。然后把该文件里每一处 `actor = _actor(request)` 改成 `actor = await _actor(request)`（用 `grep -n "_actor(request)"` 找全；所有调用处都在 `async def` 里）。

`sessions_router.py` 四处 `actor = authenticate(request)` → `actor = await authenticate_active(request)`，import 同步改。`composition/today/router.py:64` 同样处理。

`agent_access/.../router.py` 的 `resolve_session`：在 `actor = verify_session_token(...)` 之后加 `await ensure_account_active(request.app.state.database, actor.account_id)`，import `ensure_account_active`。

- [ ] **Step 5: 改 identity 路由**

`SessionResponse` 加字段：

```python
class SessionResponse(BaseModel):
    account_id: UUID
    phone: str
    family_id: UUID
    pregnancy_id: UUID | None
    role: FamilyMemberRole
    token: str
    #: 登录时顺手撤销了注销申请。客户端据此提示「欢迎回来」。
    deletion_cancelled: bool = False
```

`login` 里，在 `if account is None or not password_ok:` 之后、查家庭之前插入：

```python
        now = datetime.now(UTC)
        if not account.can_log_in(now=now):
            # 已停用 / 缓冲期已过：对外和「账号不存在」一模一样。
            raise HTTPException(status_code=401, detail=LOGIN_FAILURE)
        deletion_cancelled = account.status is AccountStatus.pending_deletion
        if deletion_cancelled:
            account.cancel_deletion()
            await family_uow.repository.save_account_status(account)
            await family_uow.commit()
```

并在最后的 `SessionResponse(...)` 里加 `deletion_cancelled=deletion_cancelled,`。文件顶部 import `AccountStatus`：`from aim_api.contexts.identity.domain.account import AccountStatus`。

在 `login` 之后新增端点：

```python
class DeletionRequest(BaseModel):
    password: str = Field(min_length=1, max_length=200)


@router.post("/api/v1/auth/deletion-request", status_code=204)
async def request_deletion(payload: DeletionRequest, request: Request) -> Response:
    """申请注销。30 天内重新登录即撤销，到期由 scripts/purge_deleted_accounts.py 删除。

    只验签、不检查状态：已在缓冲期的账号再点一次应当幂等成功，而不是 401。
    """
    actor = authenticate(request)
    database: Database = request.app.state.database

    async with database.session() as session:
        family_uow = SqlAlchemyFamilyUnitOfWork(session)
        account = await family_uow.repository.get_account(actor.account_id)
        hashed = account.password_hash if account is not None else _DUMMY_HASH
        if account is None or not verify_password(payload.password, hashed):
            raise HTTPException(status_code=401, detail=LOGIN_FAILURE)
        account.request_deletion(now=datetime.now(UTC))
        await family_uow.repository.save_account_status(account)
        await family_uow.commit()
    return Response(status_code=204)
```

import `authenticate`：`from aim_api.platform.auth.context import authenticate, issue_session_token`。

- [ ] **Step 6: 跑 identity 测试确认通过**

```bash
cd services/api && python3 -m pytest tests/integration/identity -q 2>&1 | tail -3
```

预期全部通过。

- [ ] **Step 7: 跑全部后端测试 + 导出契约**

```bash
cd services/api && python3 -m pytest -q 2>&1 | tail -3 && make lint && make contracts && git -C ../.. diff --stat contracts/
```

预期测试全绿；`contracts/public-api/openapi.json` 出现 `/api/v1/auth/deletion-request` 与 `deletion_cancelled`。

- [ ] **Step 8: 提交**

```bash
git add services/api contracts/public-api/openapi.json
git commit -m "feat(api): 注销申请接口、登录自动撤销，认证时检查账号状态"
```

---

### Task 3: 到期清理用例与脚本

**Files:**
- Create: `services/api/src/aim_api/contexts/identity/application/commands/purge_expired_deletions.py`（若 `application/commands/` 目录不存在则新建，并加空 `__init__.py`，与 `contexts/family/application/commands/` 的做法一致）
- Create: `services/api/scripts/purge_deleted_accounts.py`
- Create: `services/api/tests/integration/identity/test_purge_expired_deletions.py`

**Interfaces:**
- Produces：`PurgeSummary(account_id: UUID, families_deleted: int, families_anonymized: int)`；`async def execute(session: AsyncSession, *, now: datetime, dry_run: bool = False) -> list[PurgeSummary]`。

- [ ] **Step 1: 写失败的集成测试**

```python
from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import text

from aim_api.bootstrap import create_app
from aim_api.contexts.identity.application.commands import purge_expired_deletions
from aim_api.platform.config.settings import get_settings
from aim_api.platform.database.session import create_database

PASSWORD = "a-good-password"


def _phone() -> str:
    return "138" + str(int(uuid4()) % 10**8).zfill(8)


def _register(client: TestClient, phone: str, role: str = "mother") -> dict:
    response = client.post(
        "/api/v1/auth/register", json={"phone": phone, "password": PASSWORD, "role": role}
    )
    assert response.status_code == 201, response.text
    return response.json()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _request_deletion(client: TestClient, session: dict) -> None:
    response = client.post(
        "/api/v1/auth/deletion-request", json={"password": PASSWORD}, headers=_auth(session["token"])
    )
    assert response.status_code == 204, response.text


async def _run_purge(now: datetime, dry_run: bool = False):
    database = create_database(get_settings().database_url)
    async with database.session() as session:
        return await purge_expired_deletions.execute(session, now=now, dry_run=dry_run)


async def _count(sql: str, **params) -> int:
    database = create_database(get_settings().database_url)
    async with database.session() as session:
        return int(await session.scalar(text(sql), params) or 0)


def _later() -> datetime:
    return datetime.now(UTC) + timedelta(days=31)


def test_sole_member_family_is_deleted_entirely() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        session = _register(client, _phone())
        headers = _auth(session["token"])
        # 造一条记录和一份计划，验证它们跟着家庭一起消失。
        pregnancy = client.post(
            f"/api/v1/families/{session['family_id']}/pregnancies",
            json={"due_date": "2027-03-01"},
            headers=headers,
        )
        assert pregnancy.status_code == 201, pregnancy.text
        pregnancy_id = pregnancy.json()["id"]
        record = client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/records",
            json={
                "type": "note",
                "occurred_at": "2026-09-16T08:00:00Z",
                "visibility": "family",
                "title": "t",
                "content": "c",
                "structured_data": {},
            },
            headers=headers,
        )
        assert record.status_code == 201, record.text
        _request_deletion(client, session)

    summaries = asyncio.run(_run_purge(_later()))
    mine = [s for s in summaries if s.account_id == UUID(session["account_id"])]
    assert len(mine) == 1
    assert mine[0].families_deleted == 1 and mine[0].families_anonymized == 0

    assert asyncio.run(_count("SELECT count(*) FROM accounts WHERE id = :id", id=UUID(session["account_id"]))) == 0
    assert asyncio.run(_count("SELECT count(*) FROM families WHERE id = :id", id=UUID(session["family_id"]))) == 0
    assert asyncio.run(_count("SELECT count(*) FROM records WHERE pregnancy_id = :id", id=UUID(pregnancy_id))) == 0
    assert asyncio.run(_count("SELECT count(*) FROM pregnancies WHERE id = :id", id=UUID(pregnancy_id))) == 0


def test_family_with_other_members_is_kept_and_anonymized() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        mother = _register(client, _phone())
        mother_headers = _auth(mother["token"])
        invite = client.post(
            f"/api/v1/families/{mother['family_id']}/invitations",
            json={"phone": _phone(), "role": "father"},
            headers=mother_headers,
        )
        assert invite.status_code == 201, invite.text
        token = invite.json()["token"]
        father = _register(client, invite.json()["invitee_phone"], role="father")
        accept = client.post(
            f"/api/v1/family-invitations/{token}/accept", headers=_auth(father["token"])
        )
        assert accept.status_code == 200, accept.text

        # 妈妈是家庭创建人，还给自己指派了一条待办。
        plan = client.post(f"/api/v1/pregnancies/{mother['pregnancy_id']}/tasks",
                           json={"title": "买叶酸"}, headers=mother_headers)
        assert plan.status_code == 201, plan.text
        task = plan.json()
        assign = client.post(
            f"/api/v1/tasks/{task['id']}/assign",
            json={"expected_version": task["version"], "assigned_member_id": mother["account_id"]},
            headers=mother_headers,
        )
        assert assign.status_code == 200, assign.text
        _request_deletion(client, mother)

    summaries = asyncio.run(_run_purge(_later()))
    mine = [s for s in summaries if s.account_id == UUID(mother["account_id"])]
    assert mine and mine[0].families_anonymized == 1 and mine[0].families_deleted == 0

    assert asyncio.run(_count("SELECT count(*) FROM accounts WHERE id = :id", id=UUID(mother["account_id"]))) == 0
    assert asyncio.run(_count("SELECT count(*) FROM families WHERE id = :id", id=UUID(mother["family_id"]))) == 1
    assert asyncio.run(_count(
        "SELECT count(*) FROM families WHERE id = :id AND created_by = :father",
        id=UUID(mother["family_id"]), father=UUID(father["account_id"]),
    )) == 1
    assert asyncio.run(_count(
        "SELECT count(*) FROM tasks WHERE id = :id AND assigned_member_id IS NULL", id=UUID(task["id"])
    )) == 1


def test_accounts_still_in_grace_and_dry_run_are_untouched() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        session = _register(client, _phone())
        _request_deletion(client, session)

    assert asyncio.run(_run_purge(datetime.now(UTC) + timedelta(days=10))) == [] or all(
        s.account_id != UUID(session["account_id"])
        for s in asyncio.run(_run_purge(datetime.now(UTC) + timedelta(days=10)))
    )
    dry = asyncio.run(_run_purge(_later(), dry_run=True))
    assert any(s.account_id == UUID(session["account_id"]) for s in dry)
    assert asyncio.run(_count("SELECT count(*) FROM accounts WHERE id = :id", id=UUID(session["account_id"]))) == 1
```

注意：邀请接口的实际路径、请求体字段（`phone`/`role`）、响应里是否含 `token` 与 `invitee_phone`，以及 pregnancies/records/tasks/assign 的字段，实现前用 `grep -n "invitations\|def accept\|token" services/api/src/aim_api/contexts/family/adapters/inbound/http/router.py` 和 `contracts/public-api/openapi.json` 核对，按真实契约修正测试里的请求体；测试的意图不变。若邀请响应不回明文 token（只回 hash），改用 `services/api/tests/integration/family/` 里现成的接受邀请写法。

- [ ] **Step 2: 跑测试确认失败**

```bash
cd services/api && python3 -m pytest tests/integration/identity/test_purge_expired_deletions.py -q 2>&1 | tail -5
```

预期：`ModuleNotFoundError: … purge_expired_deletions`。

- [ ] **Step 3: 写用例**

`services/api/src/aim_api/contexts/identity/application/commands/purge_expired_deletions.py`：

```python
"""删除缓冲期已过的注销账号。

这是唯一一处跨上下文直接写表的地方。注销要把一个人从家庭、孕期、记录、计划、
对话里同时抹掉，按上下文各自暴露删除接口再逐个调，代价远大于收益；
而且它只跑在定时任务里，不在请求路径上。
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from sqlalchemy import delete, select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from aim_api.contexts.identity.domain.account import DELETION_GRACE_PERIOD, AccountStatus


@dataclass(frozen=True, slots=True)
class PurgeSummary:
    account_id: UUID
    families_deleted: int
    families_anonymized: int


async def execute(
    session: AsyncSession, *, now: datetime, dry_run: bool = False
) -> list[PurgeSummary]:
    cutoff = now - DELETION_GRACE_PERIOD
    expired = (
        await session.execute(
            text(
                "SELECT id FROM accounts "
                "WHERE status = :status AND deletion_requested_at IS NOT NULL "
                "AND deletion_requested_at <= :cutoff"
            ),
            {"status": AccountStatus.pending_deletion.value, "cutoff": cutoff},
        )
    ).scalars().all()

    summaries: list[PurgeSummary] = []
    for account_id in expired:
        summary = await _purge_one(session, UUID(str(account_id)))
        summaries.append(summary)

    if dry_run:
        await session.rollback()
    else:
        await session.commit()
    return summaries


async def _purge_one(session: AsyncSession, account_id: UUID) -> PurgeSummary:
    families_deleted = 0
    families_anonymized = 0

    # 他发出的邀请：invited_by 是 RESTRICT 外键，不删账号删不掉。
    await session.execute(
        text("DELETE FROM family_invitations WHERE invited_by = :id"), {"id": account_id}
    )

    family_ids = (
        await session.execute(
            text("SELECT family_id FROM family_members WHERE account_id = :id"), {"id": account_id}
        )
    ).scalars().all()

    for family_id in family_ids:
        others = (
            await session.execute(
                text(
                    "SELECT account_id FROM family_members "
                    "WHERE family_id = :family AND account_id <> :id "
                    "ORDER BY joined_at NULLS LAST, invited_at NULLS LAST"
                ),
                {"family": family_id, "id": account_id},
            )
        ).scalars().all()

        if others:
            await session.execute(
                text(
                    "UPDATE tasks SET assigned_member_id = NULL "
                    "WHERE assigned_member_id = :id AND pregnancy_id IN "
                    "(SELECT id FROM pregnancies WHERE family_id = :family)"
                ),
                {"id": account_id, "family": family_id},
            )
            await session.execute(
                text(
                    "UPDATE families SET created_by = :heir "
                    "WHERE id = :family AND created_by = :id"
                ),
                {"heir": others[0], "family": family_id, "id": account_id},
            )
            families_anonymized += 1
        else:
            # 唯一成员：整个家庭一起走。顺序按依赖：先叶子表，最后 families。
            await session.execute(
                text(
                    "DELETE FROM task_changes WHERE task_id IN (SELECT id FROM tasks "
                    "WHERE pregnancy_id IN (SELECT id FROM pregnancies WHERE family_id = :family))"
                ),
                {"family": family_id},
            )
            await session.execute(
                text(
                    "DELETE FROM tasks WHERE pregnancy_id IN "
                    "(SELECT id FROM pregnancies WHERE family_id = :family)"
                ),
                {"family": family_id},
            )
            await session.execute(
                text(
                    "DELETE FROM pregnancy_plans WHERE pregnancy_id IN "
                    "(SELECT id FROM pregnancies WHERE family_id = :family)"
                ),
                {"family": family_id},
            )
            await session.execute(
                text("DELETE FROM records WHERE family_id = :family"), {"family": family_id}
            )
            await session.execute(
                text(
                    "DELETE FROM pregnancy_facts WHERE pregnancy_id IN "
                    "(SELECT id FROM pregnancies WHERE family_id = :family)"
                ),
                {"family": family_id},
            )
            await session.execute(
                text("DELETE FROM pregnancies WHERE family_id = :family"), {"family": family_id}
            )
            await session.execute(
                text("DELETE FROM family_invitations WHERE family_id = :family"),
                {"family": family_id},
            )
            await session.execute(
                text("DELETE FROM agent_sessions WHERE family_id = :family"), {"family": family_id}
            )
            await session.execute(
                text("DELETE FROM families WHERE id = :family"), {"family": family_id}
            )
            families_deleted += 1

    # family_members 与 agent_sessions 对 accounts 是 CASCADE，随账号一起删。
    await session.execute(text("DELETE FROM accounts WHERE id = :id"), {"id": account_id})
    return PurgeSummary(
        account_id=account_id,
        families_deleted=families_deleted,
        families_anonymized=families_anonymized,
    )
```

`select`、`delete`、`update` 若最终没用到就从 import 里删掉（ruff 会报未使用）。

- [ ] **Step 4: 写脚本**

`services/api/scripts/purge_deleted_accounts.py`：

```python
#!/usr/bin/env python3
"""删除注销缓冲期已过（30 天）的账号。

每天由 crontab 跑一次（见 infrastructure/deploy/README.md）：

    docker exec -i aim-api-1 python scripts/purge_deleted_accounts.py
    docker exec -i aim-api-1 python scripts/purge_deleted_accounts.py --dry-run

`--dry-run` 只打印会删哪些账号，不写库。
"""

from __future__ import annotations

import asyncio
import sys
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from aim_api.contexts.identity.application.commands import purge_expired_deletions  # noqa: E402
from aim_api.platform.config.settings import get_settings  # noqa: E402
from aim_api.platform.database.session import create_database  # noqa: E402


async def run(dry_run: bool) -> int:
    database = create_database(get_settings().database_url)
    async with database.session() as session:
        summaries = await purge_expired_deletions.execute(
            session, now=datetime.now(UTC), dry_run=dry_run
        )
    prefix = "[dry-run] " if dry_run else ""
    if not summaries:
        print(f"{prefix}没有到期的注销账号")
        return 0
    for item in summaries:
        print(
            f"{prefix}账号 {item.account_id}：删除家庭 {item.families_deleted} 个，"
            f"匿名保留家庭 {item.families_anonymized} 个"
        )
    return 0


def main() -> int:
    dry_run = "--dry-run" in sys.argv[1:]
    return asyncio.run(run(dry_run))


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 5: 跑测试确认通过，跑全部后端测试与 lint**

```bash
cd services/api && python3 -m pytest tests/integration/identity/test_purge_expired_deletions.py -q 2>&1 | tail -5 && python3 -m pytest -q 2>&1 | tail -2 && make lint
```

- [ ] **Step 6: 提交**

```bash
git add services/api
git commit -m "feat(api): 到期注销账号的清理用例与脚本"
```

---

### Task 4: 法律页面、网关路由、部署与上架清单

**Files:**
- Create: `apps/legal/privacy.html`
- Create: `apps/legal/terms.html`
- Modify: `infrastructure/deploy/nginx-aim.conf`（`/agent/` 之前插入 `/legal/`）
- Modify: `infrastructure/compose/nginx-local.conf`（同上）
- Modify: `infrastructure/compose/compose.yaml:78-80`（挂载 `apps/legal`）
- Modify: `infrastructure/deploy/deploy.sh:57-67`（上传 `apps/legal`）
- Modify: `infrastructure/deploy/README.md`（新章节「上架前清单」与 crontab）

**Interfaces:**
- Produces：`GET <网关>/legal/privacy.html`、`GET <网关>/legal/terms.html`（本地 `http://127.0.0.1:8080/legal/…`）。

- [ ] **Step 1: 写隐私政策**

`apps/legal/privacy.html`：

```html
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Aim 隐私政策</title>
<style>
  body { max-width: 720px; margin: 0 auto; padding: 24px 20px 48px; font: 16px/1.7 -apple-system, "PingFang SC", "Helvetica Neue", sans-serif; color: #2C2620; background: #F6F1E9; }
  h1 { font-size: 24px; font-weight: 500; } h2 { font-size: 18px; font-weight: 500; margin-top: 28px; }
  p, li { margin: 8px 0; } .meta { color: #837A6E; font-size: 14px; }
  @media (prefers-color-scheme: dark) { body { color: #F0EAE0; background: #1A1714; } .meta { color: #A79D8F; } }
</style>
</head>
<body>
<!-- 运营主体与联系方式只写在这里，换主体只改这两行。 -->
<script>window.AIM_OPERATOR = "王韩斌"; window.AIM_CONTACT = "whb4d12@gmail.com";</script>

<h1>Aim 隐私政策</h1>
<p class="meta">更新日期：2026 年 9 月 16 日 · 生效日期：2026 年 9 月 16 日</p>
<p>Aim（以下简称「本应用」）由 <span data-operator></span>（以下简称「我们」）运营。本政策说明我们收集哪些信息、如何使用与存储、与谁共享，以及你享有的权利。使用本应用即表示你已阅读并同意本政策。</p>

<h2>一、我们收集的信息</h2>
<ul>
  <li><strong>账号信息</strong>：手机号、密码（仅以 argon2id 加密后的形式存储，我们无法查看明文）。</li>
  <li><strong>家庭信息</strong>：你在家庭中的身份（妈妈、爸爸或其他家人）、称呼，以及你邀请的家庭成员的手机号。</li>
  <li><strong>孕期信息</strong>：预产期或末次月经日期，以及据此换算的孕周。</li>
  <li><strong>健康记录</strong>：你主动记录的产检结果、身体感受、随手记、清单勾选等内容。</li>
  <li><strong>待办与计划</strong>：孕期计划、待办事项及其完成、延期、指派等变更历史。</li>
  <li><strong>与 AIM 的对话</strong>：你向应用内 AI 助手（AIM）发送的消息及其回复。</li>
</ul>
<p>本应用不收集设备通讯录、位置、相册或广告标识符，不接入任何第三方统计或广告 SDK。</p>

<h2>二、我们如何使用这些信息</h2>
<ul>
  <li>生成并维护你的孕期计划与待办，在家庭成员之间同步。</li>
  <li>由 AIM 根据你的孕周、记录和提问提供建议。AIM 的回复由第三方大语言模型服务生成（见第四条）。</li>
  <li>保障账号安全，例如登录校验与异常请求限流。</li>
</ul>
<p>我们不会将你的信息用于广告投放，也不会出售给任何第三方。</p>

<h2>三、家庭内的共享</h2>
<p>同一家庭的成员共享同一份孕期计划、待办和健康记录：你记录的内容，家庭内其他成员可以看到。请只邀请你信任的人加入家庭。与 AIM 的对话按账号隔离，其他家庭成员看不到你的对话。</p>

<h2>四、第三方处理</h2>
<p>为了生成 AIM 的回复，你的提问及相关孕期上下文会被发送给我们接入的大语言模型服务商处理。我们只发送生成回复所必需的内容，不发送你的手机号和密码。</p>

<h2>五、存储与安全</h2>
<ul>
  <li>数据存储于位于中国大陆的服务器。</li>
  <li>密码经 argon2id 加密存储；登录凭证保存在你设备的系统钥匙串中。</li>
  <li>我们采取访问控制、请求限流等措施保护数据，但任何网络传输和存储方式都无法保证绝对安全。</li>
</ul>

<h2>六、你的权利</h2>
<ul>
  <li><strong>查看与修改</strong>：你可以在应用内随时查看、修改、删除自己记录的内容，修改自己的称呼和身份。</li>
  <li><strong>注销账号</strong>：在「家庭」页的「账号」分组中可申请注销。申请后账号立即停用；30 天内重新登录可撤销申请；30 天后我们将删除你的账号信息。若你是家庭中唯一的成员，家庭及其全部孕期数据一并删除；若家庭还有其他成员，你的记录以匿名形式保留给家庭，指派给你的待办变为未指派。</li>
  <li><strong>其他请求</strong>：你可以通过下方联系方式提出数据副本、更正或删除的请求，我们会在 15 个工作日内回复。</li>
</ul>

<h2>七、未成年人</h2>
<p>本应用面向成年用户，不面向 14 周岁以下的儿童。如我们发现在未经监护人同意的情况下收集了儿童的个人信息，会尽快删除。</p>

<h2>八、本政策的更新</h2>
<p>本政策可能随功能变化而更新。重大变更时我们会在应用内提示。继续使用本应用即视为接受更新后的政策。</p>

<h2>九、联系我们</h2>
<p>运营者：<span data-operator></span><br>邮箱：<a data-contact href="#"></a></p>

<script>
  document.querySelectorAll("[data-operator]").forEach(function (el) { el.textContent = window.AIM_OPERATOR; });
  document.querySelectorAll("[data-contact]").forEach(function (el) { el.textContent = window.AIM_CONTACT; el.href = "mailto:" + window.AIM_CONTACT; });
</script>
</body>
</html>
```

- [ ] **Step 2: 写用户协议**

`apps/legal/terms.html`：

```html
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Aim 用户协议</title>
<style>
  body { max-width: 720px; margin: 0 auto; padding: 24px 20px 48px; font: 16px/1.7 -apple-system, "PingFang SC", "Helvetica Neue", sans-serif; color: #2C2620; background: #F6F1E9; }
  h1 { font-size: 24px; font-weight: 500; } h2 { font-size: 18px; font-weight: 500; margin-top: 28px; }
  p, li { margin: 8px 0; } .meta { color: #837A6E; font-size: 14px; }
  .notice { border: 1px solid #BC5F3A; border-radius: 12px; padding: 12px 16px; margin: 16px 0; }
  @media (prefers-color-scheme: dark) { body { color: #F0EAE0; background: #1A1714; } .meta { color: #A79D8F; } .notice { border-color: #D97D52; } }
</style>
</head>
<body>
<!-- 运营主体与联系方式只写在这里，换主体只改这两行。 -->
<script>window.AIM_OPERATOR = "王韩斌"; window.AIM_CONTACT = "whb4d12@gmail.com";</script>

<h1>Aim 用户协议</h1>
<p class="meta">更新日期：2026 年 9 月 16 日 · 生效日期：2026 年 9 月 16 日</p>
<p>欢迎使用 Aim（以下简称「本应用」）。本应用由 <span data-operator></span>（以下简称「我们」）运营。注册或使用本应用即表示你同意本协议及《隐私政策》。</p>

<div class="notice">
  <strong>医疗免责声明</strong>
  <p>本应用提供的孕期计划、知识内容以及 AI 助手（AIM）的回复，仅供一般性参考，<strong>不构成医疗诊断、治疗建议或处方</strong>，不能替代医生、助产士或其他专业医疗人员的意见。任何关于用药、检查、处置的决定，请务必咨询医生。如出现出血、剧烈腹痛、胎动明显减少、持续头痛或视物模糊等紧急情况，请<strong>立即就医或拨打急救电话</strong>，不要等待应用的回复。</p>
</div>

<h2>一、服务内容</h2>
<p>本应用为孕期家庭提供孕周计算、孕期计划与待办、健康记录、家庭协作以及 AI 助手问答等功能。功能可能随版本更新而调整。</p>

<h2>二、账号</h2>
<ul>
  <li>你需要使用手机号和密码注册账号，并对账号下的所有活动负责。请妥善保管密码；密码丢失需联系我们重置。</li>
  <li>你应保证注册信息真实有效。一个家庭由若干账号组成，家庭内成员共享孕期计划与记录。</li>
  <li>你可以随时在应用内申请注销账号，规则见《隐私政策》。</li>
</ul>

<h2>三、AI 助手</h2>
<p>AIM 的回复由大语言模型生成，可能存在错误、过时或不适用于你个人情况的内容。AIM 在你明确确认后才会修改涉及医疗、付费或不可逆的计划项，但你仍需自行判断其建议是否适合你。</p>

<h2>四、使用规范</h2>
<p>你不得利用本应用从事违法违规活动，不得上传侵犯他人权利或含有违法内容的信息，不得干扰本应用的正常运行。我们有权对违规账号采取限制或终止服务的措施。</p>

<h2>五、知识产权</h2>
<p>本应用的软件、界面、内置的孕期任务与知识内容受著作权法保护。你记录的内容归你所有，你授权我们为提供服务之目的存储和处理这些内容。</p>

<h2>六、服务变更与终止</h2>
<p>我们可能因维护、升级或不可抗力暂停服务，并尽量提前告知。若本应用终止运营，我们会提前 30 天在应用内公告，并在终止后依照《隐私政策》删除用户数据。</p>

<h2>七、责任限制</h2>
<p>在法律允许的范围内，我们对因使用或无法使用本应用而产生的任何间接损失不承担责任。本应用按「现状」提供，不对内容的准确性、完整性作出保证。</p>

<h2>八、争议解决</h2>
<p>本协议适用中华人民共和国法律。因本协议产生的争议，双方应先友好协商；协商不成的，提交我们所在地有管辖权的人民法院解决。</p>

<h2>九、联系我们</h2>
<p>运营者：<span data-operator></span><br>邮箱：<a data-contact href="#"></a></p>

<script>
  document.querySelectorAll("[data-operator]").forEach(function (el) { el.textContent = window.AIM_OPERATOR; });
  document.querySelectorAll("[data-contact]").forEach(function (el) { el.textContent = window.AIM_CONTACT; el.href = "mailto:" + window.AIM_CONTACT; });
</script>
</body>
</html>
```

- [ ] **Step 3: 网关路由**

`infrastructure/deploy/nginx-aim.conf`，在 `location /agent/ {` 那段之前插入：

```nginx
    # 隐私政策与用户协议。App Store Connect 要一个可公开访问的隐私政策 URL，
    # 注册页与家庭页也从这里打开。纯静态文件，不走 API。
    location /legal/ {
        alias /opt/aim/legal/;
        add_header Cache-Control "no-cache";
    }
```

`infrastructure/compose/nginx-local.conf`，在 `location /agent/ {` 之前插入：

```nginx
    location /legal/ {
        alias /srv/legal/;
    }
```

`infrastructure/compose/compose.yaml` 的 gateway `volumes` 加一行：

```yaml
      - ../../apps/legal:/srv/legal:ro
```

- [ ] **Step 4: 部署脚本与文档**

`infrastructure/deploy/deploy.sh`，在上传前端产物的 `REMOTE_SCRIPT` 段之后加：

```bash
say "上传法律页面到 /opt/aim/legal"
LEGAL_TARBALL="$(mktemp -t aim-legal)"
trap 'rm -f "$TARBALL" "$WEB_TARBALL" "$LEGAL_TARBALL"' EXIT
tar -czf "$LEGAL_TARBALL" -C apps/legal .
scp_ -q "$LEGAL_TARBALL" "${REMOTE}:/tmp/aim-legal.tar.gz"
ssh_ "$REMOTE" bash -euo pipefail <<'REMOTE_SCRIPT'
  rm -rf /opt/aim/legal
  mkdir -p /opt/aim/legal
  tar -xzf /tmp/aim-legal.tar.gz -C /opt/aim/legal
  rm -f /tmp/aim-legal.tar.gz
  chmod -R a+rX /opt/aim/legal
REMOTE_SCRIPT
```

（原来的 `trap 'rm -f "$TARBALL" "$WEB_TARBALL"' EXIT` 删掉，用上面这条替代。）

`infrastructure/deploy/README.md` 在「## 安全现状」之前新增章节：

```markdown
## 定时任务

注销账号有 30 天缓冲期，到期删除由脚本完成。服务器上加一条 crontab（每天 04:00）：

```
0 4 * * * docker exec -i aim-api-1 python scripts/purge_deleted_accounts.py >> /var/log/aim-purge.log 2>&1
```

先用 `--dry-run` 看一眼会删哪些账号再正式启用。

## 上架前清单

按顺序，前两项周期最长，先启动：

1. **域名 + HTTPS**：给后端配域名和证书，nginx 监听 443；`apps/ios/AimApp/Config/Endpoints.local.xcconfig` 的 `AIM_REMOTE_BASE_URL` 改成 `https://…`；然后删掉 `apps/ios/AimApp/Resources/Info.plist` 里整个 `NSAppTransportSecurity` 段。生产后端还是裸 IP 时**不能**删。
2. **ICP 备案**：域名备案 + App 备案，主体须与 Apple 开发者账号主体一致。
3. **Apple Developer Program** 付费账号；`apps/ios/AimApp.xcodeproj/project.pbxproj` 的 `DEVELOPMENT_TEAM` 换成该团队。
4. 部署上面的 crontab。
5. **App Store Connect**：隐私政策 URL 填 `https://<域名>/legal/privacy.html`；隐私标签勾选「手机号」「用户 ID」「健康与健身」「其他用户内容」，均为「与用户关联」「用于 App 功能」，不用于追踪；审核备注附一个测试账号，并说明医疗免责声明在用户协议与 AIM 页面头部两处。
6. 每次上传新构建前递增 `CURRENT_PROJECT_VERSION`（pbxproj 里两处）。
```

- [ ] **Step 5: 本地验证**

```bash
docker compose --env-file .env --profile local -f infrastructure/compose/compose.yaml up -d gateway 2>&1 | tail -2
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/legal/privacy.html
curl -s http://127.0.0.1:8080/legal/terms.html | grep -c "医疗免责声明"
nginx -t -c "$PWD/infrastructure/deploy/nginx-aim.conf" 2>&1 | tail -1 || true
```

预期：`200`、`1`。最后一条 `nginx -t` 本机没装 nginx 时会失败，可忽略（生产配置由 deploy 时的 `nginx -t` 检查）。

- [ ] **Step 6: 提交**

```bash
git add apps/legal infrastructure
git commit -m "feat(infra): 隐私政策与用户协议页面、网关路由、上架前清单"
```

---

### Task 5: iOS 数据层：`deletion_cancelled`、注销请求、法律页地址

**Files:**
- Modify: `apps/ios/AimApp/Features/Onboarding/OnboardingStore.swift:4-20`（`SessionResponse`）
- Modify: `apps/ios/AimApp/Clients/BusinessAPIClient/BusinessRepository.swift`（协议 + actor）
- Modify: 所有 `BusinessRepositoryProtocol` 测试替身：`Tests/LibraryStoreTests.swift`（3 个）、`Tests/AgentActivityLogTests.swift`、`Tests/RecordStoreTests.swift`、`Tests/TimelineStoreTests.swift`（`StubTimelineRepository`）
- Modify: `apps/ios/AimApp/Features/Agent/AgentWebScheme.swift`
- Create: `apps/ios/AimApp/Tests/SessionResponseTests.swift`、`apps/ios/AimApp/Tests/LegalPagesTests.swift`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`（两个测试文件按「pbxproj 约定」登记）

**Interfaces:**
- Produces：`SessionResponse.deletionCancelled: Bool`（缺省 false）；`BusinessRepositoryProtocol.requestAccountDeletion(password: String) async throws`；`enum LegalPage { case privacy, terms }` 与 `AgentWebScheme.legalURL(_ page: LegalPage, gateway: URL) -> URL`；`APIEnvironment.gatewayURL`（若已有同义属性则复用，实施时 `grep -n "gateway" apps/ios/AimApp/Core/Networking/APIEnvironment.swift apps/ios/AimApp/Features/Agent/AgentView.swift` 找 AgentView 现在怎么得到网关 URL，照用）。

- [ ] **Step 1: 写失败的测试**

`Tests/SessionResponseTests.swift`：

```swift
import XCTest
@testable import AimApp

final class SessionResponseTests: XCTestCase {
    private let base = """
    {
      "account_id": "11111111-1111-1111-1111-111111111111",
      "phone": "13800000001",
      "family_id": "22222222-2222-2222-2222-222222222222",
      "pregnancy_id": null,
      "role": "mother",
      "token": "aim.v1.demo"
    """

    func testDeletionCancelledDefaultsToFalseWhenMissing() throws {
        let data = (base + "}").data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder.aim.decode(SessionResponse.self, from: data).deletionCancelled)
    }

    func testDeletionCancelledIsDecoded() throws {
        let data = (base + ", \"deletion_cancelled\": true}").data(using: .utf8)!
        XCTAssertTrue(try JSONDecoder.aim.decode(SessionResponse.self, from: data).deletionCancelled)
    }
}
```

`Tests/LegalPagesTests.swift`：

```swift
import XCTest
@testable import AimApp

final class LegalPagesTests: XCTestCase {
    func testLegalURLsLiveUnderTheGatewayLegalPath() {
        let gateway = URL(string: "http://127.0.0.1:8080")!
        XCTAssertEqual(AgentWebScheme.legalURL(.privacy, gateway: gateway).absoluteString,
                       "http://127.0.0.1:8080/legal/privacy.html")
        XCTAssertEqual(AgentWebScheme.legalURL(.terms, gateway: gateway).absoluteString,
                       "http://127.0.0.1:8080/legal/terms.html")
    }

    func testLegalURLIgnoresTrailingSlashOnGateway() {
        let gateway = URL(string: "http://121.40.205.28/")!
        XCTAssertEqual(AgentWebScheme.legalURL(.terms, gateway: gateway).absoluteString,
                       "http://121.40.205.28/legal/terms.html")
    }
}
```

登记两个测试文件到 pbxproj（`A1/A2…0141`、`A1/A2…0142`，Tests 分组，测试目标 Sources `A3…0006`）。

- [ ] **Step 2: 跑测试确认编译失败**

```bash
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests/SessionResponseTests -only-testing:AimAppTests/LegalPagesTests test 2>&1 | grep -E "error:|TEST" | head
```

预期：`has no member 'deletionCancelled'`、`cannot find 'LegalPage'`。

- [ ] **Step 3: 实现**

`SessionResponse` 改为：

```swift
struct SessionResponse: Decodable, Sendable {
    let accountID: UUID
    let phone: String
    let familyID: UUID
    let pregnancyID: UUID?
    let role: FamilyRole
    let token: String
    /// 登录时服务端顺手撤销了注销申请。旧服务端没有这个字段，缺省为 false。
    let deletionCancelled: Bool

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case phone
        case familyID = "family_id"
        case pregnancyID = "pregnancy_id"
        case role
        case token
        case deletionCancelled = "deletion_cancelled"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try container.decode(UUID.self, forKey: .accountID)
        phone = try container.decode(String.self, forKey: .phone)
        familyID = try container.decode(UUID.self, forKey: .familyID)
        pregnancyID = try container.decodeIfPresent(UUID.self, forKey: .pregnancyID)
        role = try container.decode(FamilyRole.self, forKey: .role)
        token = try container.decode(String.self, forKey: .token)
        deletionCancelled = try container.decodeIfPresent(Bool.self, forKey: .deletionCancelled) ?? false
    }
}
```

`AgentWebScheme.swift` 追加：

```swift
enum LegalPage: String {
    case privacy = "privacy.html"
    case terms = "terms.html"

    var title: String {
        switch self {
        case .privacy: "隐私政策"
        case .terms: "用户协议"
        }
    }
}

extension AgentWebScheme {
    /// 法律页面和对话面一样由网关提供，路径对应 nginx 的 `location /legal/`。
    static func legalURL(_ page: LegalPage, gateway: URL) -> URL {
        URL(string: "/legal/" + page.rawValue, relativeTo: gateway)!.absoluteURL
    }
}
```

`BusinessRepositoryProtocol` 在 `updateMyMembership` 之后加：

```swift
    func requestAccountDeletion(password: String) async throws
```

actor 实现（放在 `updateMyMembership` 之后）：

```swift
    /// 申请注销。服务端进入 30 天缓冲期，旧票立即失效，所以调用方成功后要 `session.clear()`。
    func requestAccountDeletion(password: String) async throws {
        struct Body: Encodable { let password: String }
        let request = environment.businessRequest(
            path: "/api/v1/auth/deletion-request", method: "POST",
            body: try encoder.encode(Body(password: password)))
        _ = try await session.aimData(for: request)
    }
```

所有测试替身各加一行（与其邻居风格一致）：

```swift
    func requestAccountDeletion(password: String) async throws { throw APIError.notConfigured }
```

`grep -rn "BusinessRepositoryProtocol" apps/ios/AimApp/Tests` 找全所有 conformer。

- [ ] **Step 4: 跑测试确认通过 + 全部单元测试**

```bash
make ios-parse && xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests test 2>&1 | grep -E "error:|Executed|TEST" | tail -3
```

预期 `** TEST SUCCEEDED **`，用例数比之前多 4。

- [ ] **Step 5: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): 会话响应带 deletion_cancelled，仓储支持申请注销，法律页地址"
```

---

### Task 6: 注册页同意勾选与法律页打开

**Files:**
- Modify: `apps/ios/AimApp/Features/Onboarding/AuthForm.swift`
- Modify: `apps/ios/AimApp/Tests/AuthFormTests.swift`
- Modify: `apps/ios/AimApp/Features/Onboarding/OnboardingView.swift`
- Modify: `apps/ios/AimApp/Features/Onboarding/OnboardingStore.swift`（`validationHint`）
- Create: `apps/ios/AimApp/Core/DesignSystem/Components/SafariView.swift`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`（`SafariView.swift` → `A1/A2…0139`，Components 分组，App Sources）

**Interfaces:**
- Consumes：`LegalPage`、`AgentWebScheme.legalURL`（Task 5）。
- Produces：`AuthForm.agreedToTerms: Bool`（默认 false，注册必需）；`struct SafariView: UIViewControllerRepresentable`（`init(url: URL)`）；`extension View { func legalPageSheet(_ page: Binding<LegalPage?>, gateway: URL) -> some View }`。
- 标识符：同意开关 `auth-consent`，两个链接按钮 `auth-open-terms`、`auth-open-privacy`。

- [ ] **Step 1: 写失败的表单测试**

`AuthFormTests.swift` 的 `form(...)` 助手加参数 `agreedToTerms: Bool = true` 并传给 `AuthForm(...)`；追加：

```swift
    /// App Store 与个人信息保护法都要求注册前明确同意。登录不用再点一次。
    func testRegistrationRequiresAgreeingToTerms() {
        XCTAssertFalse(form(agreedToTerms: false).canSubmit)
        XCTAssertTrue(form(agreedToTerms: true).canSubmit)
    }

    func testLoginDoesNotRequireAgreeingAgain() {
        XCTAssertTrue(form(mode: .login, role: nil, agreedToTerms: false).canSubmit)
    }
```

- [ ] **Step 2: 跑测试确认编译失败**

```bash
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests/AuthFormTests test 2>&1 | grep -E "error:|TEST" | head -3
```

- [ ] **Step 3: 改 `AuthForm`**

在 `var nickname = ""` 后加：

```swift
    /// 注册前必须勾选「已阅读并同意用户协议与隐私政策」。
    var agreedToTerms = false
```

`canSubmit` 的 `.register` 分支改为：

```swift
        case .register:
            return password.count >= Self.minPasswordLength && role != nil && agreedToTerms
```

`OnboardingStore.validationHint` 在角色检查之后加：

```swift
        if form.mode == .register, !form.agreedToTerms { return "请先阅读并同意用户协议和隐私政策" }
```

- [ ] **Step 4: `SafariView` 与 sheet 修饰符**

`Core/DesignSystem/Components/SafariView.swift`：

```swift
import SafariServices
import SwiftUI

/// 用系统的 Safari 视图打开网页。法律页面这类只读内容用它最省事：
/// 分享、阅读模式、返回都是系统的，不用自己维护一个 WKWebView 外壳。
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Color.aimAccent)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension LegalPage: Identifiable {
    var id: String { rawValue }
}

extension View {
    /// 绑定一个 `LegalPage?`，非 nil 时弹出对应页面。
    func legalPageSheet(_ page: Binding<LegalPage?>, gateway: URL) -> some View {
        sheet(item: page) { selected in
            SafariView(url: AgentWebScheme.legalURL(selected, gateway: gateway))
                .ignoresSafeArea()
        }
    }
}
```

- [ ] **Step 5: 注册页**

`OnboardingView` 加 `@State private var legalPage: LegalPage?`。在提交按钮的 `Section` 之前、错误信息 `Section` 之后加：

```swift
                if store.form.mode == .register {
                    Section {
                        Toggle(isOn: $store.form.agreedToTerms) {
                            // 两个书名号各自可点；Toggle 的标签区域点击不改变开关状态，
                            // 所以链接按钮放在标签里不会误触。
                            HStack(spacing: 0) {
                                Text("我已阅读并同意")
                                Button("《用户协议》") { legalPage = .terms }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.aimAccent)
                                    .accessibilityIdentifier("auth-open-terms")
                                Text("和")
                                Button("《隐私政策》") { legalPage = .privacy }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.aimAccent)
                                    .accessibilityIdentifier("auth-open-privacy")
                            }
                            .font(.footnote)
                        }
                        .tint(Color.aimAccent)
                        .accessibilityIdentifier("auth-consent")
                    }
                    .listRowBackground(Color.clear)
                }
```

`NavigationStack` 末尾（`.background(Color.aimCanvas)` 之后）加 `.legalPageSheet($legalPage, gateway: session.environment.gatewayURL)`。`gatewayURL` 的名字按 Task 5 接口块里的核对结果使用（AgentView 已经在用同一个东西打开 `/agent/`）。

- [ ] **Step 6: 登记 pbxproj、编译、跑测试**

```bash
make ios-parse && make ios-build 2>&1 | grep -E "error:|BUILD" | tail -2 && xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests/AuthFormTests test 2>&1 | grep -E "error:|Executed|TEST" | tail -2
```

- [ ] **Step 7: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): 注册前须同意用户协议与隐私政策，可在应用内查看"
```

---

### Task 7: 家庭页「账号」分组：法律页、退出登录、注销

**Files:**
- Create: `apps/ios/AimApp/Features/Family/AccountSection.swift`
- Modify: `apps/ios/AimApp/Features/Family/FamilyView.swift:37-41`（List 里加分组）、`:9-31`（sheet）
- Modify: `apps/ios/AimApp/App/AppSessionStore.swift`（`signOutNotice`、`welcomeBackNotice`）
- Modify: `apps/ios/AimApp/Features/Onboarding/OnboardingStore.swift:52-62`（登录后写 `welcomeBackNotice`）
- Modify: `apps/ios/AimApp/Features/Onboarding/OnboardingView.swift`（显示 `signOutNotice`）
- Modify: `apps/ios/AimApp/Features/Home/HomeView.swift`（进入后显示 `welcomeBackNotice` toast）
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`（`AccountSection.swift` → `A1/A2…0138`，Family 分组，App Sources）

**Interfaces:**
- Consumes：`requestAccountDeletion(password:)`、`LegalPage`、`legalPageSheet`、`SafariView`。
- Produces：`AppSessionStore.signOutNotice: String?`（登录页显示一次）、`AppSessionStore.welcomeBackNotice: String?`（首页 toast 一次）；`AccountSection(repository: BusinessRepositoryProtocol?, gateway: URL)`。
- 标识符：`account-open-privacy`、`account-open-terms`、`account-sign-out`、`account-delete`、`account-delete-confirm`（确认对话框按钮）、`account-delete-password`、`account-delete-submit`、`auth-notice`（登录页提示）、`home-welcome-back`（toast）。

- [ ] **Step 1: `AppSessionStore` 加两条一次性提示**

在 `var isOffline = false` 之后加：

```swift
    /// 退出或注销后回到登录页要说一句话；登录页读一次就清掉。不持久化。
    var signOutNotice: String?
    /// 登录时服务端撤销了注销申请，进首页提示一次。
    var welcomeBackNotice: String?
```

`clear()` 不动它们（`clear()` 在注销流程里先于设置 notice 调用，顺序见 Step 3）。

- [ ] **Step 2: `AccountSection`**

```swift
import SwiftUI

/// 家庭页底部的「账号」分组：法律页、退出登录、注销。
///
/// 注销走两步确认：先说清 30 天规则，再要一次密码。密码不是为了防别人——
/// 手机已经解锁了——而是为了防手滑：这是全 App 唯一一个会让家人也丢数据的操作。
struct AccountSection: View {
    @Environment(AppSessionStore.self) private var session
    let repository: BusinessRepositoryProtocol?
    let gateway: URL

    @State private var legalPage: LegalPage?
    @State private var confirmingDeletion = false
    @State private var enteringPassword = false

    var body: some View {
        Section("账号") {
            Button { legalPage = .privacy } label: { Label("隐私政策", systemImage: "hand.raised") }
                .accessibilityIdentifier("account-open-privacy")
            Button { legalPage = .terms } label: { Label("用户协议", systemImage: "doc.text") }
                .accessibilityIdentifier("account-open-terms")
            Button {
                session.clear()
                session.signOutNotice = "已退出登录"
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .accessibilityIdentifier("account-sign-out")
            Button(role: .destructive) { confirmingDeletion = true } label: {
                Label("注销账号", systemImage: "person.crop.circle.badge.xmark")
            }
            .accessibilityIdentifier("account-delete")
        }
        .legalPageSheet($legalPage, gateway: gateway)
        .confirmationDialog(
            "注销账号",
            isPresented: $confirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("继续注销", role: .destructive) { enteringPassword = true }
                .accessibilityIdentifier("account-delete-confirm")
            Button("取消", role: .cancel) {}
        } message: {
            Text("账号会立即停用。30 天内重新登录可以撤销；30 天后账号和你的个人数据将被删除。")
        }
        .sheet(isPresented: $enteringPassword) {
            DeleteAccountSheet(repository: repository) {
                enteringPassword = false
                session.clear()
                session.signOutNotice = "注销申请已提交。30 天内重新登录可撤销，之后数据将被删除。"
            }
        }
    }
}

private struct DeleteAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let repository: BusinessRepositoryProtocol?
    let onDeleted: () -> Void

    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("输入密码以确认", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("account-delete-password")
                } footer: {
                    Text("提交后会退回登录页。")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.aimDanger) }
                }
            }
            .navigationTitle("确认注销")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("注销", role: .destructive) { Task { await submit() } }
                            .disabled(password.isEmpty)
                            .accessibilityIdentifier("account-delete-submit")
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() async {
        guard let repository else {
            errorMessage = "网络还没准备好，稍后再试。"
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await repository.requestAccountDeletion(password: password)
            onDeleted()
        } catch let error as APIError {
            if case let .http(status, _) = error, status == 401 {
                errorMessage = "密码不对"
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

`APIError` 的 case 名按 `grep -n "case http" apps/ios/AimApp/Core/Networking/*.swift` 核对（`OnboardingStore.message(for:)` 里用的是 `case let .http(status, _)`）。

- [ ] **Step 3: 接入 `FamilyView`**

`familyContent` 的 `List` 里 `inviteSection` 之后加 `AccountSection(repository: store.repository, gateway: session.environment.gatewayURL)`（`FamilyStore.repository` 的类型按 `grep -n "var repository" apps/ios/AimApp/Features/Family/FamilyStore.swift` 核对；`gatewayURL` 名字同 Task 5）。

- [ ] **Step 4: 登录页与首页的提示**

`OnboardingView`：在 `Form` 最顶部（方式 `Picker` 之前）加：

```swift
                if let notice = session.signOutNotice {
                    Section {
                        Text(notice)
                            .font(.subheadline)
                            .foregroundStyle(Color.aimTextSecondary)
                            .accessibilityIdentifier("auth-notice")
                    }
                    .listRowBackground(Color.clear)
                }
```

并在 `NavigationStack` 上加 `.onDisappear { session.signOutNotice = nil }`。

`OnboardingStore.submit` 在 `appSession.configure(...)` 之前加：

```swift
            if response.deletionCancelled {
                appSession.welcomeBackNotice = "欢迎回来，注销申请已取消"
            }
```

`HomeView`：在 `.task(id: session.pregnancyID)` 旁加：

```swift
            .onAppear {
                if let notice = session.welcomeBackNotice {
                    toast = AimToastMessage(text: notice, undoTitle: "", accessibilityIdentifier: "home-welcome-back")
                    session.welcomeBackNotice = nil
                }
            }
```

- [ ] **Step 5: 登记 pbxproj、编译、全部单元测试**

```bash
make ios-parse && make ios-build 2>&1 | grep -E "error:|BUILD" | tail -2 && xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests test 2>&1 | grep -E "error:|Executed|TEST" | tail -2
```

- [ ] **Step 6: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): 家庭页账号分组：法律页、退出登录、30 天缓冲注销"
```

---

### Task 8: Agent 免责声明与打包元数据

**Files:**
- Modify: `apps/ios/AimApp/Features/Agent/AgentView.swift:55-64`
- Modify: `apps/ios/AimApp/Resources/Info.plist`
- Create: `apps/ios/AimApp/Resources/PrivacyInfo.xcprivacy`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`（`MARKETING_VERSION`；`PrivacyInfo.xcprivacy` → `A1/A2…0140`，Resources 分组与 `A30000000000000000000005 /* Resources */`）

- [ ] **Step 1: 免责声明**

`AgentView.header` 的 `VStack` 里，`Text("孕期里的事，说一声就好")` 之后加：

```swift
                Text("AIM 的建议不能替代医生诊断，紧急情况请立即就医")
                    .font(.caption2)
                    .foregroundStyle(Color.aimTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("agent-disclaimer")
```

- [ ] **Step 2: Info.plist**

在 `AIMRemoteBaseURL` 之后加：

```xml
	<!-- 只用系统 HTTPS/TLS，属于豁免加密；声明了就不用每次上传都答问卷。 -->
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
```

`NSAppTransportSecurity` 段**保留**。

- [ ] **Step 3: 隐私清单**

`apps/ios/AimApp/Resources/PrivacyInfo.xcprivacy`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypePhoneNumber</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeUserID</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeHealth</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeOtherUserContent</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
		</dict>
	</array>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array><string>CA92.1</string></array>
		</dict>
	</array>
</dict>
</plist>
```

pbxproj：`PBXBuildFile` 加 `A20000000000000000000140 /* Resources/PrivacyInfo.xcprivacy in Resources */ = {isa = PBXBuildFile; fileRef = A10000000000000000000140 /* Resources/PrivacyInfo.xcprivacy */; };`；`PBXFileReference` 加 `A10000000000000000000140 /* Resources/PrivacyInfo.xcprivacy */ = {isa = PBXFileReference; lastKnownFileType = text.xml; path = Resources/PrivacyInfo.xcprivacy; sourceTree = "<group>"; };`；含 `Resources/Info.plist` 的分组 children 加 `A10000000000000000000140`；`A30000000000000000000005 /* Resources */` 的 files 加 `A20000000000000000000140`。

- [ ] **Step 4: 版本号**

pbxproj 里 AimApp 目标的两个配置（含 `CURRENT_PROJECT_VERSION = 1;` 且 `PRODUCT_BUNDLE_IDENTIFIER = com.aim.pregnancy;` 的那两个 buildSettings 块，约第 1513 与 1542 行）各加一行 `MARKETING_VERSION = 1.0.0;`（放在 `CURRENT_PROJECT_VERSION` 之后，按字母序）。

- [ ] **Step 5: 验证**

```bash
plutil -lint apps/ios/AimApp/Resources/PrivacyInfo.xcprivacy apps/ios/AimApp/Resources/Info.plist
make ios-parse && make ios-build 2>&1 | grep -E "error:|warning: .*rivacy|BUILD" | tail -3
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -showBuildSettings 2>/dev/null | grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION"
ls /tmp/aim-derived-data/Build/Products/Debug-iphonesimulator/AimApp.app/PrivacyInfo.xcprivacy
```

预期：两个 plist 合法；BUILD SUCCEEDED；`MARKETING_VERSION = 1.0.0`；隐私清单被拷进 .app。

- [ ] **Step 6: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): AIM 页面医疗免责声明，隐私清单、版本号与出口合规声明"
```

---

### Task 9: UI 测试：注册同意、注销流程；全量回归

**Files:**
- Modify: `apps/ios/AimApp/UITests/CoreJourneyUITests.swift`（`registerNewAccount` 助手、新增用例）

前置：`make dev` 运行中（含网关）；API 侧 Task 2 已部署到本地栈——本地栈用的是镜像里的代码，**改了后端要重建**：`docker compose --env-file .env --profile local -f infrastructure/compose/compose.yaml up -d --build api`，然后 `docker exec -i aim-api-1 alembic upgrade head`（或确认容器启动时自动跑迁移：`grep -n "alembic\|migrate" infrastructure/compose/compose.yaml services/api/Dockerfile`）。

- [ ] **Step 1: 助手勾选同意**

`registerNewAccount` 里，在选完身份、点提交之前加：

```swift
        // 注册前必须同意协议。Toggle 在无障碍树里是 switch。
        let consent = app.switches["auth-consent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5), "注册页应当有同意开关")
        if (consent.value as? String) != "1" { consent.tap() }
```

若 `app.switches["auth-consent"]` 找不到（SwiftUI 有时把标识符挂在外层），改用 `app.descendants(matching: .any).matching(identifier: "auth-consent").firstMatch` 并对其 `.switches.firstMatch` 点击。

- [ ] **Step 2: 新增用例**

```swift
    /// App Store 审核指南 5.1.1(v)：能注册就必须能在 App 内注销。
    /// 30 天缓冲：注销后马上用同一账号登录，应当恢复并提示。
    func testAccountCanBeDeletedAndRestoredWithinGracePeriod() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        let phone = registerNewAccountReturningPhone(in: app)
        completePregnancySetup(in: app)

        let familyTab = app.tabBars.buttons["家庭"]
        XCTAssertTrue(familyTab.waitForExistence(timeout: 15))
        familyTab.tap()

        let deleteButton = app.buttons["account-delete"]
        reveal(deleteButton, in: app)
        deleteButton.tap()
        let confirm = app.buttons["account-delete-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let passwordField = app.secureTextFields["account-delete-password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.tap()
        passwordField.typeText("aim-test-password")
        app.buttons["account-delete-submit"].tap()

        // 回到登录页，带一句提示。
        let notice = app.staticTexts["auth-notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "注销后应回到登录页并提示")

        // 缓冲期内登录 → 恢复。
        app.buttons["登录"].firstMatch.tap()   // segmented picker 的「登录」段
        let phoneField = app.textFields["auth-phone"]
        phoneField.tap()
        phoneField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        phoneField.typeText(phone)
        let password = app.secureTextFields["auth-password"]
        password.tap()
        password.typeText("aim-test-password")
        dismissKeyboard(in: app)
        app.buttons["auth-submit"].tap()

        let welcome = app.descendants(matching: .any).matching(identifier: "home-welcome-back").firstMatch
        XCTAssertTrue(welcome.waitForExistence(timeout: 15), "缓冲期内登录应提示注销已取消")
    }

    /// 未勾选同意时不能注册。
    func testRegistrationIsBlockedUntilTermsAreAccepted() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        let phone = app.textFields["auth-phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 10))
        phone.tap()
        phone.typeText("139\(Int.random(in: 10_000_000...99_999_999))")
        let password = app.secureTextFields["auth-password"]
        password.tap()
        password.typeText("aim-test-password")
        dismissKeyboard(in: app)
        app.buttons["auth-role"].tap()
        app.buttons["妈妈"].tap()

        let submit = app.buttons["auth-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled, "没勾同意不该能注册")
        let consent = app.switches["auth-consent"]
        consent.tap()
        XCTAssertTrue(submit.isEnabled)
    }
```

`registerNewAccountReturningPhone` 是把现有 `registerNewAccount` 的手机号生成提出来的版本：把 `registerNewAccount` 改成先生成 `let phone = "139\(Int.random(...))"`，末尾 `return phone`（返回值 `@discardableResult`），并给它起别名：

```swift
    @discardableResult
    private func registerNewAccount(in app: XCUIApplication, role: String = "妈妈", nickname: String? = nil) -> String { … 原实现，末尾 return phone … }
    private func registerNewAccountReturningPhone(in app: XCUIApplication) -> String { registerNewAccount(in: app) }
```

`app.buttons["登录"].firstMatch` 若命中的是别的按钮，改为 `app.segmentedControls.buttons["登录"]` 或 `app.buttons.matching(identifier: "auth-mode-picker").buttons["登录"]`——用 `po app` 的树确认。

- [ ] **Step 3: 跑新用例与受影响用例**

```bash
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppUITests/CoreJourneyUITests/testAccountCanBeDeletedAndRestoredWithinGracePeriod -only-testing:AimAppUITests/CoreJourneyUITests/testRegistrationIsBlockedUntilTermsAreAccepted -only-testing:AimAppUITests/CoreJourneyUITests/testQuickAddCreatesATaskInTodayGroup test 2>&1 | grep -E "error:|passed|failed|Executed|TEST"
```

- [ ] **Step 4: 全量 UI 回归**

```bash
xcodebuild … -only-testing:AimAppUITests test 2>&1 | grep -E "passed|failed|Executed|TEST"
```

预期：除既有的 `testGlobalAgentButtonShowsCurrentTabContext`、`testAPastConversationCanBeReopenedFromHistory` 两条外全部通过。

- [ ] **Step 5: 提交**

```bash
git add apps/ios/AimApp/UITests/CoreJourneyUITests.swift
git commit -m "test(ios): 注册须同意协议、注销后缓冲期内登录恢复的 UI 用例"
```

---

### Task 10: 全量验证与文档收口

**Files:**
- Modify: `README.md`（一句话提到注销与法律页面）
- Modify: `apps/ios/README.md`（同上）

- [ ] **Step 1: 全量验证**

```bash
cd services/api && python3 -m pytest -q 2>&1 | tail -2 && make lint && cd ../..
make ios-parse && make ios-build 2>&1 | grep -E "error:|BUILD" | tail -1
xcodebuild … -only-testing:AimAppTests test 2>&1 | grep -E "Executed|TEST" | tail -2
git status --short   # 应为空
```

- [ ] **Step 2: README**

根 `README.md` 末段（讲注册登录的那段）追加一句：「注册需同意《用户协议》和《隐私政策》（`apps/legal/`，由网关 `/legal/` 提供）；家庭页可退出登录或申请注销，注销有 30 天缓冲期，到期由 `services/api/scripts/purge_deleted_accounts.py` 清理。」`apps/ios/README.md` 的功能列表加一行「账号：法律页、退出登录、注销（30 天缓冲）」。

- [ ] **Step 3: 提交**

```bash
git add README.md apps/ios/README.md
git commit -m "docs: 说明注册同意、注销缓冲期与法律页面"
```

---

## 自检记录

- 规格 §3.1–3.2 → Task 1、2；§3.3 → Task 3；§3.4 → Task 5、7；§4.1–4.2 → Task 4、5；§4.3 → Task 6、9；§5 → Task 8；§6 → Task 8；§7 → Task 4；§8 测试 → Task 1、2、3、5、6、9；§9 不做项未出现在任何任务；§10 验收 1–6 分别由 Task 2/3/9、4、6/9、8、8、4 覆盖。
- 类型一致性：`SessionResponse.deletionCancelled`（Task 5）被 Task 7 的 `OnboardingStore` 使用；`requestAccountDeletion(password:)`（Task 5）被 Task 7 使用；`LegalPage` / `legalURL` / `legalPageSheet`（Task 5、6）被 Task 6、7 使用；`authenticate_active` / `ensure_account_active`（Task 2）在 Task 2 内全部接线；`purge_expired_deletions.execute(session, now=, dry_run=)`（Task 3）被脚本与测试使用。
- Task 3 的测试依赖邀请与接受邀请的真实契约，已在步骤里要求实施前核对；这是有意留给实施者的核对点，不是占位。
