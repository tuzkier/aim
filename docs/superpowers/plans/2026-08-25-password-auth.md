# 密码账号体系 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this
> plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用手机号 + 密码替换掉免密的演示登录，并让用户在注册时选择家庭角色和称呼。

**Architecture:** 密码哈希独立成 `platform/auth/passwords.py`，与签发 token 的
`platform/auth/context.py` 平级。identity 的 HTTP 层用 register / login 两个端点替换
demo-session。家庭角色和称呼是同一次注册流程的一部分，因此同批实现。

**Tech Stack:** FastAPI · SQLAlchemy + Alembic · argon2-cffi · SwiftUI · XCTest

## Global Constraints

- 密码最短 8 位，不设组合要求
- 哈希算法 argon2id，不用 bcrypt（72 字节静默截断）
- 登录失败一律返回同一条消息，不区分账号不存在与密码错误
- token 有效期 30 天（2592000 秒）
- 只能修改自己的成员信息
- 后端测试跑在 conftest 的一次性库上，不碰开发库
- iOS 模拟器与测试连本地栈，真机连部署环境（地址见 `infrastructure/deploy/README.md`）

---

## File Structure

| 文件 | 职责 |
|---|---|
| `services/api/src/aim_api/platform/auth/passwords.py` | 新建。argon2id 哈希与校验、密码长度规则 |
| `services/api/src/aim_api/platform/auth/context.py` | 改。token 有效期 3600 → 2592000 |
| `services/api/migrations/versions/*_password_and_nickname.py` | 新建。`accounts.password_hash`、`family_members.nickname` |
| `services/api/src/aim_api/contexts/identity/domain/account.py` | 改。Account 带 password_hash |
| `services/api/src/aim_api/contexts/identity/adapters/inbound/http/router.py` | 改。register / login 取代 demo-session |
| `services/api/src/aim_api/contexts/family/domain/family.py` | 改。FamilyMember 带 nickname |
| `services/api/src/aim_api/contexts/family/adapters/inbound/http/router.py` | 改。两个 PATCH 端点 |
| `services/api/scripts/reset_password.py` | 新建。命令行重置密码 |
| `infrastructure/deploy/nginx-aim.conf` | 改。限流改前缀匹配 |
| `apps/ios/AimApp/Features/Auth/AuthView.swift` | 新建。登录 / 注册两段 |
| `apps/ios/AimApp/Features/Auth/AuthStore.swift` | 新建。调 register / login |
| `apps/ios/AimApp/Features/Family/FamilyView.swift` | 改。改家庭名、改自己的称呼和角色 |
| `apps/ios/AimApp/UITests/CoreJourneyUITests.swift` | 改。14 个用例改走真实注册 |

---

## Task 1: 密码哈希

**Files:**
- Create: `services/api/src/aim_api/platform/auth/passwords.py`
- Test: `services/api/tests/platform/test_passwords.py`
- Modify: `services/api/pyproject.toml`（显式声明 `argon2-cffi`）

**Interfaces:**
- Produces: `hash_password(raw: str) -> str`、`verify_password(raw: str, hashed: str) -> bool`、
  `PasswordTooShort`（异常）、`MIN_PASSWORD_LENGTH = 8`

- [ ] **Step 1: 写失败测试**

```python
import pytest
from aim_api.platform.auth.passwords import (
    MIN_PASSWORD_LENGTH, PasswordTooShort, hash_password, verify_password,
)

def test_hash_is_not_the_password_itself() -> None:
    hashed = hash_password("correct horse battery")
    assert "correct horse battery" not in hashed
    assert hashed.startswith("$argon2id$")

def test_verify_accepts_the_right_password() -> None:
    assert verify_password("correct horse battery", hash_password("correct horse battery"))

def test_verify_rejects_the_wrong_password() -> None:
    assert not verify_password("wrong", hash_password("correct horse battery"))

def test_same_password_hashes_differently_each_time() -> None:
    # 加盐的意义：两个用同样密码的账号，拖库时不能一眼看出是同一个密码。
    assert hash_password("same-password") != hash_password("same-password")

def test_short_passwords_are_rejected() -> None:
    with pytest.raises(PasswordTooShort):
        hash_password("a" * (MIN_PASSWORD_LENGTH - 1))

def test_long_passwords_are_not_truncated() -> None:
    # bcrypt 在 72 字节处静默截断，argon2 不会。这条钉住选型理由。
    base = "x" * 80
    assert not verify_password(base + "DIFFERENT", hash_password(base + "ORIGINAL"))
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd services/api && python3 -m pytest tests/platform/test_passwords.py -q`
Expected: FAIL — `ModuleNotFoundError: aim_api.platform.auth.passwords`

- [ ] **Step 3: 实现**

```python
"""密码哈希。

用 argon2id 而不是 bcrypt：bcrypt 在 72 字节处静默截断，超长密码会被无声削弱，
而用户不会得到任何提示。
"""

from __future__ import annotations

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, VerificationError, InvalidHashError

MIN_PASSWORD_LENGTH = 8

_hasher = PasswordHasher()


class PasswordTooShort(ValueError):
    """密码短于 MIN_PASSWORD_LENGTH。"""


def hash_password(raw: str) -> str:
    if len(raw) < MIN_PASSWORD_LENGTH:
        raise PasswordTooShort(f"password must be at least {MIN_PASSWORD_LENGTH} characters")
    return _hasher.hash(raw)


def verify_password(raw: str, hashed: str) -> bool:
    try:
        return _hasher.verify(hashed, raw)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd services/api && python3 -m pytest tests/platform/test_passwords.py -q`
Expected: 6 passed

- [ ] **Step 5: 提交**

```bash
git add services/api/src/aim_api/platform/auth/passwords.py services/api/tests/platform/test_passwords.py services/api/pyproject.toml
git commit -m "feat(api): argon2id 密码哈希"
```

---

## Task 2: 数据库迁移

**Files:**
- Create: `services/api/migrations/versions/<rev>_password_and_nickname.py`

**Interfaces:**
- Produces: `accounts.password_hash TEXT NOT NULL`、`family_members.nickname VARCHAR(60) NULL`

`password_hash` 设为 NOT NULL 且不给默认值。库当前为空，无存量行需要回填；给默认值反而
会让「没有密码的账号」这种非法状态可表达。

- [ ] **Step 1: 生成迁移骨架**

Run: `cd services/api && DATABASE_URL='postgresql+asyncpg://aim:aim@127.0.0.1:55434/aim' alembic revision -m "password and nickname"`

- [ ] **Step 2: 写 upgrade / downgrade**

```python
def upgrade() -> None:
    op.add_column("accounts", sa.Column("password_hash", sa.Text(), nullable=False))
    op.add_column("family_members", sa.Column("nickname", sa.String(length=60), nullable=True))


def downgrade() -> None:
    op.drop_column("family_members", "nickname")
    op.drop_column("accounts", "password_hash")
```

- [ ] **Step 3: 验证迁移能跑通且可回滚**

Run: `cd services/api && python3 -m pytest tests/integration/test_database_isolation.py -q`
（conftest 每次新建库并跑 `upgrade head`，这条通过即证明迁移可用）
Expected: PASS

- [ ] **Step 4: 提交**

```bash
git add services/api/migrations/versions/
git commit -m "feat(api): accounts.password_hash 与 family_members.nickname"
```

---

## Task 3: 注册接口

**Files:**
- Modify: `services/api/src/aim_api/contexts/identity/adapters/inbound/http/router.py`
- Modify: `services/api/src/aim_api/contexts/identity/domain/account.py`
- Test: `services/api/tests/integration/identity/test_register.py`

**Interfaces:**
- Consumes: `hash_password`（Task 1）
- Produces: `POST /api/v1/auth/register`，请求体
  `{phone, password, role, nickname?, due_date?}`，响应体沿用现有
  `{account_id, phone, family_id, pregnancy_id, role, token}`

- [ ] **Step 1: 写失败测试**

```python
from __future__ import annotations
from uuid import uuid4
from fastapi.testclient import TestClient
from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings

def _phone() -> str:
    return "138" + str(int(uuid4()) % 10**8).zfill(8)

def _register(client: TestClient, **overrides: object):
    body = {"phone": _phone(), "password": "a-good-password", "role": "mother"}
    body.update(overrides)
    return client.post("/api/v1/auth/register", json=body)

def test_register_creates_account_family_and_token() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        response = _register(client)
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["token"].startswith("aim.v1.")
        assert body["family_id"]
        assert body["role"] == "mother"

def test_register_rejects_a_duplicate_phone() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        phone = _phone()
        assert _register(client, phone=phone).status_code == 201
        assert _register(client, phone=phone).status_code == 409

def test_register_rejects_a_short_password() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        assert _register(client, password="short").status_code == 422

def test_register_accepts_every_role() -> None:
    # 角色以前写死成 mother，爸爸和其他家人根本没法注册。
    with TestClient(create_app(settings=get_settings())) as client:
        for role in ("mother", "father", "other_caregiver"):
            assert _register(client, role=role).json()["role"] == role

def test_register_stores_the_nickname() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        body = _register(client, role="other_caregiver", nickname="婆婆").json()
        family = client.get(
            f"/api/v1/families/{body['family_id']}",
            headers={"Authorization": f"Bearer {body['token']}"},
        ).json()
        assert family["members"][0]["nickname"] == "婆婆"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd services/api && python3 -m pytest tests/integration/identity/test_register.py -q`
Expected: FAIL — 404 Not Found（端点尚不存在）

- [ ] **Step 3: 实现端点**

复用现有 `_ensure_family_and_pregnancy` / `_ensure_initial_plan`，把写死的
`FamilyMemberRole.mother` 换成请求里的 `role`，并把 `nickname` 透传给
`CreateFamilyCommand`。密码用 `hash_password` 存进 `accounts.password_hash`。
手机号已存在时返回 409。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd services/api && python3 -m pytest tests/integration/identity/test_register.py -q`
Expected: 5 passed

- [ ] **Step 5: 提交**

```bash
git add services/api/src services/api/tests
git commit -m "feat(api): 注册接口，支持角色与称呼"
```

---

## Task 4: 登录接口

**Files:**
- Modify: `services/api/src/aim_api/contexts/identity/adapters/inbound/http/router.py`
- Test: `services/api/tests/integration/identity/test_login.py`

**Interfaces:**
- Consumes: `verify_password`（Task 1）、`POST /api/v1/auth/register`（Task 3）
- Produces: `POST /api/v1/auth/login`，请求体 `{phone, password}`

- [ ] **Step 1: 写失败测试**

```python
LOGIN_FAILURE = "手机号或密码不对"

def test_login_returns_a_token() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        phone = _phone()
        _register(client, phone=phone, password="a-good-password")
        response = client.post(
            "/api/v1/auth/login", json={"phone": phone, "password": "a-good-password"}
        )
        assert response.status_code == 200, response.text
        assert response.json()["token"].startswith("aim.v1.")

def test_wrong_password_and_unknown_phone_are_indistinguishable() -> None:
    # 区分开这两种情况，登录接口就成了手机号枚举器。
    with TestClient(create_app(settings=get_settings())) as client:
        phone = _phone()
        _register(client, phone=phone, password="a-good-password")
        wrong = client.post("/api/v1/auth/login", json={"phone": phone, "password": "nope-nope"})
        unknown = client.post("/api/v1/auth/login", json={"phone": _phone(), "password": "nope-nope"})
        assert wrong.status_code == unknown.status_code == 401
        assert wrong.json() == unknown.json()
        assert LOGIN_FAILURE in wrong.text
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd services/api && python3 -m pytest tests/integration/identity/test_login.py -q`
Expected: FAIL — 404

- [ ] **Step 3: 实现**

账号不存在时也要走一次 `verify_password`（拿一个固定的假哈希），否则响应时间会泄露
手机号是否已注册——时序差异同样是枚举通道。

- [ ] **Step 4: 跑测试确认通过**

Expected: 2 passed

- [ ] **Step 5: 提交**

```bash
git commit -am "feat(api): 登录接口，失败响应不可区分"
```

---

## Task 5: 删除演示登录，token 改 30 天

**Files:**
- Modify: `services/api/src/aim_api/contexts/identity/adapters/inbound/http/router.py`
- Modify: `services/api/src/aim_api/platform/auth/context.py:39`
- Modify: `services/api/src/aim_api/platform/config/settings.py:27`
- Delete: `services/api/tests/integration/identity/test_demo_session.py`
- Test: `services/api/tests/platform/test_session_token.py`

- [ ] **Step 1: 写失败测试**

```python
SESSION_TTL_SECONDS = 30 * 24 * 3600

def test_session_lasts_thirty_days() -> None:
    # 原来是 1 小时。免密时代无所谓，加了密码就变成每小时手输一次。
    token = issue_session_token(uuid4(), "13800000000", "secret", now=0)
    assert decode_session_token(token, "secret").expires_at == SESSION_TTL_SECONDS

def test_demo_session_endpoint_is_gone() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        assert client.post("/api/v1/auth/demo-session", json={"phone": "13800000000"}).status_code == 404
```

- [ ] **Step 2: 跑测试确认失败**
- [ ] **Step 3: 改 3600 → `30 * 24 * 3600`，删掉 demo-session 端点、`DEV_AUTH_ENABLED` 设置项与其测试**
- [ ] **Step 4: 跑全量后端测试**

Run: `cd services/api && python3 -m pytest -q`
Expected: 全绿（demo-session 相关用例已删除）

- [ ] **Step 5: 提交**

```bash
git commit -am "feat(api)!: 删除演示登录，会话改为 30 天"
```

---

## Task 6: 改家庭名与自己的成员信息

**Files:**
- Modify: `services/api/src/aim_api/contexts/family/adapters/inbound/http/router.py`
- Modify: `services/api/src/aim_api/contexts/family/domain/family.py`
- Test: `services/api/tests/integration/family/test_family_profile.py`

**Interfaces:**
- Produces: `PATCH /api/v1/families/{family_id}` 体 `{name}`；
  `PATCH /api/v1/families/{family_id}/members/me` 体 `{nickname?, role?}`

- [ ] **Step 1: 写失败测试**

```python
def test_family_can_be_renamed() -> None:
    ...  # 注册 → PATCH name="王家" → GET 断言 name == "王家"

def test_member_can_change_their_own_nickname_and_role() -> None:
    ...  # 注册为 mother → PATCH role=father, nickname="爸爸" → 断言生效

def test_a_member_cannot_edit_someone_else() -> None:
    # 端点是 /members/me，没有 member_id 入口；改别人需要权限模型，本次不做。
    ...  # 用 A 的 token 去 PATCH B 的家庭 → 403
```

- [ ] **Step 2–5:** 同前：跑失败 → 实现 → 跑通过 → 提交

---

## Task 7: 密码重置脚本与 nginx 限流

**Files:**
- Create: `services/api/scripts/reset_password.py`
- Modify: `infrastructure/deploy/nginx-aim.conf:20-22`

- [ ] **Step 1: 写脚本**

```python
"""重置某个手机号的密码。没有短信也没有邮箱，这是唯一的找回路径。

用法：docker exec -i aim-api-1 python scripts/reset_password.py 13800000000 新密码
"""
```

- [ ] **Step 2: nginx 改前缀匹配**

```nginx
location /api/v1/auth/ {
    limit_req zone=aim_login burst=3 nodelay;
    limit_req_status 429;
    proxy_pass http://127.0.0.1:8100;
    ...
}
```

删掉原来的 `location = /api/v1/auth/demo-session`。不改的话注册和登录会落到
`location /api/` 的 20r/s 那档，等于对着密码接口敞开暴力破解。

- [ ] **Step 3: 用 `nginx -t` 校验配置**
- [ ] **Step 4: 提交**

---

## Task 8: iOS 登录 / 注册界面

**Files:**
- Create: `apps/ios/AimApp/Features/Auth/AuthStore.swift`
- Create: `apps/ios/AimApp/Features/Auth/AuthView.swift`
- Test: `apps/ios/AimApp/Tests/AuthStoreTests.swift`

**Interfaces:**
- Produces: `AuthStore.register(phone:password:role:nickname:) async -> Bool`、
  `AuthStore.login(phone:password:) async -> Bool`、`AuthMode { login, register }`

- [ ] **Step 1: 写失败单测**（表单校验：手机号位数、密码 8 位、注册时角色必选）
- [ ] **Step 2: 跑失败**
- [ ] **Step 3: 实现 store 与视图**（密码用 `SecureField`；角色用 segmented Picker；称呼选填）
- [ ] **Step 4: 跑通过**
- [ ] **Step 5: 提交**

---

## Task 9: iOS 家庭页

**Files:**
- Modify: `apps/ios/AimApp/Features/Family/FamilyView.swift`
- Modify: `apps/ios/AimApp/Features/Family/FamilyStore.swift`

- [ ] **Step 1–5:** 成员行显示称呼（空则回退角色名）；加「改家庭名」与「改我的称呼和角色」两个入口

---

## Task 10: 改写 14 个 UI 用例

**Files:**
- Modify: `apps/ios/AimApp/UITests/CoreJourneyUITests.swift`

14 个用例目前都靠 `app.textFields["手机号"]` + 「开始体验」进入。demo-session 删除后
必须改走注册：手机号 + 密码 + 角色。抽一个 `registerNewAccount(in:role:)` 辅助方法，
14 处共用，避免同样的流程写 14 遍。

- [ ] **Step 1: 抽辅助方法并改掉全部 14 处**
- [ ] **Step 2: 跑全量 iOS 测试**

Run: `xcodebuild ... test`
Expected: 单测 + UI 用例全绿

- [ ] **Step 3: 提交**

---

## Task 11: 部署与真机验证

- [ ] **Step 1: 上传代码并重建 api 容器**
- [ ] **Step 2: 跑 `alembic upgrade head`（容器启动时自动执行）**
- [ ] **Step 3: reload nginx**
- [ ] **Step 4: curl 实跑注册 / 登录 / 错密码 / 重复手机号**
- [ ] **Step 5: 装到真机，走一遍注册 → 选角色 → 填预产期**
- [ ] **Step 6: 确认 `/api/v1/auth/demo-session` 返回 404**
