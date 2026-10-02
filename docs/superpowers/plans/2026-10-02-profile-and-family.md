# 个人资料与家庭交互 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 新增个人资料页（改称呼身份、改预产期、账号设置），走通按手机号的家庭邀请，家庭页加入成员详情、家庭动态、退出与移出。

**做法：** 后端在家庭模块补齐邀请状态与成员事件；跨模块的「清理家庭 / 成员离开 / 家庭动态 / 成员详情」放在 `composition/family`（与 `composition/today` 同层），复用注销清理里已有的手写 SQL 思路并抽成共用函数。App 端新增 5 个 Swift 文件，家庭页重排，个人资料页承接原「账号」分组。

**技术栈：** FastAPI + SQLAlchemy + Alembic；SwiftUI；Eve 指令（Markdown）。

**规格：** `docs/superpowers/specs/2026-10-02-profile-and-family-design.md`

## 全局约束

- 用户可见文案一律简体中文；手机号展示一律打码为 `138****5678`（前 3 后 4）。
- 一个账号始终恰好属于一个在籍家庭；注册、登录接口不改。
- 管理员 = `families.created_by`。
- 邀请有效期 7 天；状态 `pending` / `declined` / `accepted` / `expired` / `revoked`。
- 预产期换算一律按 280 天；可保存范围：服务端今天对应孕周在 0 周 0 天到 42 周 0 天之间（含两端）。
- 与 `records` 表一致，新表不设外键；注销清理显式删除。
- iOS 不随意新增文件：本计划只新增 `ProfileView.swift`、`DueDateEditor.swift`、`MemberDetailView.swift`、`FamilyActivityView.swift`、`InvitationViews.swift` 五个，均在 `project.pbxproj` 手工登记（四处：PBXBuildFile、PBXFileReference、group children、Sources build phase），编号沿用 `A1…`/`A2…` 递增。
- 提交信息沿用仓库风格中文。

## 运行测试

- API：`make -C services/api test`（需本地栈），单文件 `cd services/api && PYTHONPATH=src python3 -m pytest <路径> -q`
- 契约：`make -C services/api contracts`
- Agent：`cd services/agent && npm test`
- iOS 单元：`xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath /tmp/aim-dd CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests test`

## 文件结构

**services/api**
- `migrations/versions/0011_family_events_and_invitations.py`（新）
- `contexts/family/domain/events.py`（新）：`FamilyEvent`、`FamilyEventKind`
- `contexts/family/domain/invitation.py`：7 天、`declined`/`revoked`、`decline()`/`revoke()`、`accept()` 允许 `declined`
- `contexts/family/application/commands/invite_member.py`：不再插 pending 成员；作废同号旧邀请
- `contexts/family/adapters/outbound/persistence/{models,repositories}.py`：`FamilyEventModel`、邀请查询方法、事件写入
- `contexts/pregnancy/domain/pregnancy.py`：`change_due_date()`
- `contexts/pregnancy/domain/errors.py`：`DueDateOutOfRange`
- `contexts/planning/adapters/outbound/persistence/{models,repositories}.py`：`created_by_actor_type/id`
- `composition/family/membership.py`（新）：`family_has_content`、`delete_family`、`detach_member`、`create_empty_family`
- `composition/family/activity.py`（新）：动态查询
- `composition/family/router.py`（新）：`/me`、`/me/invitations*`、改预产期、离开、移出、撤回、成员详情、动态
- `contexts/family/adapters/inbound/http/router.py`：`GET /families/{id}` 增加 `is_admin`、`invitations`
- `contexts/identity/application/commands/purge_expired_deletions.py`：改用 `delete_family`，并删 `family_events`
- `contexts/agent_access/adapters/inbound/http/sessions_router.py`：按家庭过滤
- `bootstrap.py`：注册新路由
- 测试：`tests/integration/family/test_invitations_flow.py`、`test_membership_exit.py`、`test_family_activity.py`、`tests/integration/pregnancy/test_due_date_update.py`、`tests/domain/family/test_invitation_states.py`

**services/agent**：`agent/instructions.md` 一句话。

**apps/ios**
- `Clients/BusinessAPIClient/BusinessRepository.swift`：新模型与方法
- 测试替身（`AimApp/Tests` 里实现 `BusinessRepositoryProtocol` 的类型）补新方法
- `App/AppSessionStore.swift`：`switchFamily`、`familyNotice`
- `App/AimApp.swift`：邀请弹窗与被移出处理挂在 `MainTabView`
- `Features/Onboarding/PregnancySetupModel.swift`：`.currentWeek` 模式
- `Features/Onboarding/PregnancySetupView.swift`：顶部待处理邀请
- `Features/Family/FamilyStore.swift`：新操作
- `Features/Family/FamilyView.swift`：重排
- `Features/Family/AccountSection.swift`：弹层改挂到个人资料页
- 新：`ProfileView.swift`、`DueDateEditor.swift`、`MemberDetailView.swift`、`FamilyActivityView.swift`、`InvitationViews.swift`
- 测试：`Tests/FamilyStoreTests.swift`（如无则加到现有 `Tests` 文件）、`Tests/PregnancySetupModelTests.swift`（已有则追加）、`UITests/CoreJourneyUITests.swift`

---

### Task 1：家庭事件表、邀请状态、待办创建人

**Files:** 迁移 0011、`family/domain/events.py`、`family/domain/invitation.py`、`invite_member.py`、家庭持久化、待办持久化；测试 `tests/domain/family/test_invitation_states.py`、`tests/integration/family/test_invitations_flow.py`（发邀请部分）

**Interfaces:**
- Produces:
  - `FamilyEventKind(StrEnum)`: `member_joined`、`member_left`、`member_removed`、`due_date_changed`
  - `FamilyEvent(id, family_id, kind, actor_account_id, subject_account_id, payload: dict, created_at)`，`FamilyEvent.new(family_id, kind, *, actor, subject=None, payload=None, now=None)`
  - `SqlAlchemyFamilyRepository.add_event(event)`、`list_invitations_for_family(family_id)`、`list_invitations_for_phone(phone)`、`get_invitation(invitation_id)`、`revoke_open_invitations(family_id, phone)`
  - `Invitation.decline()`、`Invitation.revoke()`、`Invitation.is_open(now) -> bool`（`pending`/`declined` 且未过期）、`Invitation.accept()` 接受 `declined`
  - 表 `tasks` 新列 `created_by_actor_type`（非空，回填 `changed_by_actor_type`）、`created_by_actor_id`（可空，回填 `changed_by_actor_id`）

- [ ] **Step 1：领域测试**

```python
# tests/domain/family/test_invitation_states.py
from datetime import UTC, datetime, timedelta
from uuid import uuid4
import pytest
from aim_api.contexts.family.domain.errors import InvitationExpired
from aim_api.contexts.family.domain.family import FamilyMemberRole
from aim_api.contexts.family.domain.invitation import Invitation, InvitationStatus

NOW = datetime(2026, 10, 2, tzinfo=UTC)

def _invitation():
    return Invitation.create(invitation_id=uuid4(), family_id=uuid4(), invited_by=uuid4(),
        invitee_phone="13800001111", role=FamilyMemberRole.father, token_hash="h", created_at=NOW)

def test_lasts_seven_days():
    assert _invitation().expires_at == NOW + timedelta(days=7)

def test_declined_can_still_be_accepted():
    inv = _invitation(); inv.decline()
    assert inv.status is InvitationStatus.declined and inv.is_open(NOW)
    inv.accept(uuid4(), "13800001111", NOW + timedelta(days=1))
    assert inv.status is InvitationStatus.accepted

def test_revoked_cannot_be_accepted():
    inv = _invitation(); inv.revoke()
    assert not inv.is_open(NOW)
    with pytest.raises(InvitationExpired):
        inv.accept(uuid4(), "13800001111", NOW)
```

- [ ] **Step 2：确认失败**（`pytest tests/domain/family/test_invitation_states.py`）
- [ ] **Step 3：实现** `InvitationStatus` 加 `declined`、`revoked`；`create` 用 `timedelta(days=7)`；`is_open`；`decline`（仅 `pending` 可）、`revoke`（`pending`/`declined` 可）；`accept` 前置条件改为 `status in {pending, declined}`，`revoked` 抛 `InvitationExpired("invitation was revoked")`。`events.py` 写 `FamilyEvent`。迁移 0011：建 `family_events`（列见规格 §4，索引 `ix_family_events_family_created (family_id, created_at)`）；`tasks` 加两列并 `UPDATE tasks SET created_by_actor_type = changed_by_actor_type, created_by_actor_id = changed_by_actor_id`；`DELETE FROM family_members WHERE status = 'pending'`。`TaskModel` 加两列，`SqlAlchemyPlanningRepository` 新建待办时写入当前 `changed_by_*`。`invite_member`：去掉插 pending 成员；先 `revoke_open_invitations(family_id, phone)`；被邀请人已是在籍成员仍报 `DuplicateFamilyMember`。
- [ ] **Step 4：集成测试**（`test_invitations_flow.py` 第一部分）：发两次邀请给同一号码，第一条变 `revoked`；被邀请人已注册时家庭成员里不出现 pending 行。
- [ ] **Step 5：全量通过后提交** `feat(api): 家庭事件表、邀请 7 天与暂不/撤回状态、待办记录创建人`

---

### Task 2：改预产期与 `GET /me`

**Files:** `pregnancy/domain/pregnancy.py`、`pregnancy/domain/errors.py`、孕期仓储 `save_due_date`、`composition/family/router.py`（新建，先放这两个接口）、`bootstrap.py`；测试 `tests/integration/pregnancy/test_due_date_update.py`

**Interfaces:**
- Produces: `Pregnancy.change_due_date(new: date, *, today: date) -> date`（返回旧值；范围外抛 `DueDateOutOfRange`）；`PATCH /api/v1/pregnancies/{id}` 请求 `{due_date}` 返回 `PregnancyResponse`；`GET /api/v1/me` 返回 `{account_id, family_id, pregnancy_id, role}`

- [ ] **Step 1：测试**

```python
# tests/integration/pregnancy/test_due_date_update.py（夹具同 test_batch_tools._scope）
def test_any_member_moves_the_due_date_and_it_is_logged(): ...
    # PATCH due_date=today+60d → 200，GET pregnancy 显示新 due_date 与新孕周
    # family_events 有一条 due_date_changed，payload {"from": 旧, "to": 新}
def test_out_of_range_is_rejected(): ...
    # today+300d（孕周为负）→ 422；today-20d（超 42 周）→ 422
def test_outsiders_cannot_change_it(): ...  # 另一家庭的人 → 403
def test_me_reports_current_family_and_pregnancy(): ...
```

- [ ] **Step 2–4：** 实现与通过。范围检查：`age = gestational_age(new, today)`，要求 `0 <= age.weeks*7+age.days <= 42*7`；注意 `gestational_age` 对负值截到 0，所以先用 `(today - lmp).days` 原值判断。路由在 `composition/family/router.py`：用同一 session 构造 `SqlAlchemyPregnancyUnitOfWork` 与 `SqlAlchemyFamilyRepository`，成员校验后改日期、写事件、一次提交。
- [ ] **Step 5：提交** `feat(api): 家里任何成员可改预产期并记入家庭动态；新增 GET /me`

---

### Task 3：成员离开、清理家庭、接受/暂不/撤回邀请

**Files:** `composition/family/membership.py`、`composition/family/router.py`、`purge_expired_deletions.py`；测试 `test_invitations_flow.py`（接受部分）、`test_membership_exit.py`

**Interfaces:**
- Produces:
  - `async family_has_content(session, family_id, account_id) -> str | None`（`None` 表示没有内容；否则返回中文原因）
  - `async delete_family(session, family_id) -> None`（按依赖顺序删 task_changes、tasks、pregnancy_plans、attachments、records、pregnancy_facts、pregnancies、family_invitations、family_events、tool_invocations、agent_sessions、family_members、families）
  - `async detach_member(session, family_id, account_id) -> None`（取消指派、删该人私密记录及其附件、删成员行、若是管理员转给最早加入的在籍成员）
  - `async create_empty_family(session, account_id, role, nickname) -> UUID`
  - 接口：`GET /api/v1/me/invitations`、`POST /api/v1/me/invitations/{id}/accept|decline`、`POST /api/v1/families/{id}/members/me/leave`、`DELETE /api/v1/families/{id}/members/{account_id}`、`DELETE /api/v1/families/{id}/invitations/{invitation_id}`

- [ ] **Step 1：测试**（关键用例）
  - 新注册的 B（空家庭）查 `me/invitations` 看到 A 的邀请，`can_accept=true`；接受后 B 的 `GET /me` 返回 A 的家庭，B 原家庭行已删除，A 的家庭有 `member_joined` 事件。
  - B 原家庭有一条记录 → `can_accept=false`、原因含「记录」；强行 accept → 409。
  - B 暂不后再接受仍成功；A 撤回后 B 接受 → 409「邀请已撤回」。
  - 非管理员移出别人 → 403；管理员移出 B → B 的待办变未指派、B 的私密记录删除、B `GET /me` 得到新空家庭（无孕期）、事件 `member_removed`。
  - A（管理员）退出 → 管理员转给 B；只剩一人时退出 → 409。
  - 注销清理（唯一成员）仍删除全部数据，含 `family_events`（在现有注销测试里加断言）。
- [ ] **Step 2–4：** 实现与通过。`purge_expired_deletions` 的唯一成员分支改为调用 `delete_family`；多人分支保留原逻辑（它还要匿名化，不完全等同于离开）。
- [ ] **Step 5：提交** `feat(api): 按手机号接受邀请、暂不与撤回；退出与移出家庭，管理员自动转移`

---

### Task 4：家庭详情、成员详情、家庭动态、对话历史按家庭

**Files:** 家庭路由、`composition/family/activity.py`、`composition/family/router.py`、`sessions_router.py`；测试 `test_family_activity.py`

**Interfaces:**
- Produces:
  - `GET /families/{id}`：成员加 `is_admin: bool`；新增 `invitations: [{id, phone_masked, role, invited_by, expires_at, status}]`（`pending`/`declined`，以及 7 天内过期的 `expired`）
  - `GET /families/{id}/members/{account_id}`：`{member, open_tasks: [TaskResponse], recent_records: [RecordResponse]}`
  - `GET /families/{id}/activity?before=&limit=`：`{items: [{id, kind, actor_name, title, target_type, target_id, target_deleted, created_at}], next_before}`；`kind ∈ task_created | task_completed | record_created | member_joined | member_left | member_removed | due_date_changed`；`task_created` 时 `via_agent: bool`

- [ ] **Step 1：测试**：动态合并排序、`limit` 翻页、私密记录不出现、初始计划（template）待办不出现、AIM 建的待办 `via_agent=true`、删除的记录 `target_deleted=true`；成员详情只含当前用户看得到的记录；对话历史在家庭切换后只显示新家庭的。
- [ ] **Step 2–4：** 实现与通过；`make contracts`。
- [ ] **Step 5：提交** `feat(api): 家庭详情含管理员与邀请、成员详情、家庭动态；对话历史只列当前家庭`

---

### Task 5：AIM 指令

- [ ] 在 `services/agent/agent/instructions.md` 加：If the user says the due date is wrong, tell them to change it in 家庭 → 我 → 预产期; you cannot change it yourself.
- [ ] `npm run build && npm test`，提交 `feat(agent): 预产期不对时引导用户去个人资料修改`

---

### Task 6：App 数据层

**Files:** `BusinessRepository.swift`、测试替身、`FamilyStore.swift`、`AppSessionStore.swift`、`PregnancySetupModel.swift`；测试

**Interfaces（Swift）:**
- 模型：`FamilyMember` 加 `isAdmin: Bool`（缺省 false）；`FamilySnapshot` 加 `invitations: [FamilyInvitation]`（缺省空）；`FamilyInvitation(id, phoneMasked, role, invitedBy, expiresAt, status)`；`MyInvitation(id, familyName, inviterName, role, expiresAt, canAccept, blockedReason)`；`MemberDetail(member, openTasks: [TaskItem], recentRecords: [RecordItem])`；`FamilyActivityItem(id, kind, actorName, title, targetType, targetID, targetDeleted, viaAgent, createdAt)`；`FamilyActivityPage(items, nextBefore: Date?)`；`PregnancySummary(id, dueDate, weeks, days)`；`MeResponse(familyID, pregnancyID)`
- `BusinessRepositoryProtocol` 新方法：`fetchPregnancy() -> PregnancySummary?`、`updateDueDate(_ date: Date) -> PregnancySummary`、`fetchMemberDetail(accountID:) -> MemberDetail`、`fetchActivity(before: Date?) -> FamilyActivityPage`、`revokeInvitation(id:)`、`fetchMyInvitations() -> [MyInvitation]`、`acceptInvitation(id:) -> MeResponse`、`declineInvitation(id:)`、`leaveFamily() -> MeResponse`、`removeMember(accountID:)`、`fetchMe() -> MeResponse`
- `FamilyStore`：`pregnancy`、`activity`、`hasMoreActivity`、`loadMoreActivity()`、`updateDueDate(_:) -> Bool`、`revoke(_:) -> Bool`、`remove(_:) -> Bool`、`leave() -> MeResponse?`
- `AppSessionStore.switchFamily(familyID: UUID, pregnancyID: UUID?)`、`familyNotice: String?`
- `PregnancySetupModel`：`DateMode` 加 `.currentWeek`，新增 `weeks`/`days`，`dueDate` 统一产出，`validationMessage` 用于范围

- [ ] **Step 1：单元测试**：三种模式换算（例：今天孕 31+1 → 预产期 = 今天 + 280 − (31×7+1)）、范围外有提示、`FamilyStore.updateDueDate` 成功后 `pregnancy` 更新、失败保留错误、`leave` 返回新家庭。
- [ ] **Step 2–4：** 实现，补测试替身，通过。
- [ ] **Step 5：提交** `feat(ios): 个人资料与家庭功能的数据层`

---

### Task 7：个人资料页与改预产期面板

**Files:** 新 `ProfileView.swift`、`DueDateEditor.swift`；`AccountSection.swift`（弹层挂到个人资料页）；`FamilyView.swift`（去掉账号分组和「改我的信息」，加「我」卡片入口）；`project.pbxproj`

- [ ] 个人资料页按规格 §3.2；改预产期面板按 §3.3（`.presentationDetents([.medium, .large])`，保存失败在面板内显示）。`EditMyMembershipSheet` 从 `FamilyView.swift` 挪到 `ProfileView.swift`（去掉 `private`）。
- [ ] 无障碍标识：`profile-entry`、`profile-due-date`、`due-date-mode`、`due-date-save`、`profile-edit-me`；原 `account-*` 标识保持不变。
- [ ] 构建通过，提交 `feat(ios): 个人资料页，可改称呼身份与预产期，账号设置移入`

---

### Task 8：家庭页重排、家庭动态、邀请详情

**Files:** `FamilyView.swift`、新 `FamilyActivityView.swift`、`InvitationViews.swift`

- [ ] 按规格 §3.1：家庭卡片（倒计时、进度条、头像条）、成员行（管理员标记、待办数、点进详情）、待处理邀请行（打码手机号、状态）、动态列表（滑到底加载更多，点击跳待办或记录详情，已删除的置灰）。
- [ ] 邀请详情面板（`InvitationViews.swift`）：撤回、过期重发；发邀请面板成功后提示「让 TA 用这个手机号注册或登录 AIM」。
- [ ] 提交 `feat(ios): 家庭页重新编排，加入家庭动态与邀请详情`

---

### Task 9：成员详情、退出与移出

**Files:** 新 `MemberDetailView.swift`

- [ ] 按规格 §3.4、§3.6：负责的待办（可勾选完成，复用 `PlanStore.complete`）、最近记录、本人「改称呼和身份」「退出家庭」、管理员「移出家庭」，确认框文案照规格。
- [ ] 退出成功：`session.switchFamily(...)`，`session.familyNotice = "你已退出『X』"`。
- [ ] 提交 `feat(ios): 成员详情页，可退出家庭或由管理员移出成员`

---

### Task 10：邀请弹窗与被移出处理

**Files:** `InvitationViews.swift`（`InvitationPrompt`）、`AimApp.swift`、`PregnancySetupView.swift`、`AppSessionStore.swift`

- [ ] `MainTabView` 出现时与回到前台时查 `me/invitations`，逐条弹出（未被「暂不」的）；`PregnancySetupView` 顶部列出全部有效邀请。
- [ ] 接受：`can_accept` 时确认框说明原家庭会被删除，确认后 `switchFamily`；否则显示原因与「知道了」。
- [ ] 家庭接口返回 403 时调用 `fetchMe()`，若家庭变了：`switchFamily` 并设置 `familyNotice = "你已不在『X』里"`；`RootView`/`PregnancySetupView` 读一次 `familyNotice` 显示。
- [ ] 提交 `feat(ios): 登录后弹出家庭邀请；被移出后自动回到自己的新家庭`

---

### Task 11：UI 测试与端到端验证

- [ ] 改写 `CoreJourneyUITests` 中经由家庭页「账号」分组和「改我的信息」的用例：先点 `profile-entry` 再操作。
- [ ] 新增 `testInviteeJoinsByPhone`：A 注册建档 → 邀请随机号 B → 退出 → B 用该号注册 → 填写预产期页出现邀请 → 加入 → 家庭页看到 A。
- [ ] 跑 iOS 单元测试与相关 UI 测试；后端、Agent 全量；模拟器截图检查家庭页、个人资料页、改预产期、成员详情、动态。
- [ ] 提交 `test(ios): 个人资料入口调整后的 UI 用例与按手机号加入家庭的用例`
