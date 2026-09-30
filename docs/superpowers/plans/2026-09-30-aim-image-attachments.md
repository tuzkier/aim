# AIM 支持图片 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 用户在 AIM 对话里发图片，由 `deepseek-flash` 看图处理；报告单识别后建产检记录并挂原图，原生记录详情可看原图。

**做法：** 图片在网页端压缩后，一份上传到业务服务存档（拿到附件编号），一份随消息直接发给 Eve；附件编号通过每轮附带的上下文告诉模型，模型建记录时带上编号挂图。业务服务新增附件表与本地磁盘存储，记录的 `attachment_refs` 字段正式启用。

**技术栈：** FastAPI + SQLAlchemy + Alembic；Eve 0.67.2 + zod；React + assistant-ui 附件适配器；SwiftUI。

**规格：** `docs/superpowers/specs/2026-09-30-aim-image-attachments-design.md`

## 全局约束

- 用户可见文案一律简体中文。
- 附件只收 `image/jpeg`、`image/png`、`image/webp`；单个不超过 2 MB（2 × 1024 × 1024 字节）；每条消息、每条记录最多 4 张。
- 网页压缩参数：最长边 1600 像素，JPEG 质量 0.8，统一转成 `image/jpeg`。
- 清理规则：未挂到记录且上传超过 90 天的删除；所挂记录已删除超过 30 天的删除；数据库里没有对应行、且文件修改时间超过 1 小时的孤儿文件删除。
- 查看原图只对附件所属家庭的在籍成员开放，其他人一律 404。
- 模型名 `deepseek-flash`。
- iOS 不新增 Swift 文件（`project.pbxproj` 手工登记），新类型放进既有文件。
- 提交信息沿用仓库风格：`feat(api): …`，中文描述。

## 运行测试的前置条件

- API：本地栈要起着（`make dev` 或 `docker compose … up -d`），`cd services/api && PYTHONPATH=src python3 -m pytest <路径> -q`
- Agent：`cd services/agent && npm run build && npm test`
- 网页：`cd apps/agent-web && npm test && npx tsc --noEmit`
- iOS：`xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:AimAppTests test`

## 文件结构

**services/api**
- `src/aim_api/contexts/records/domain/attachment.py`（新建）——附件实体与校验
- `src/aim_api/contexts/records/domain/errors.py`——新增 `AttachmentRejected`、`AttachmentUnavailable`
- `src/aim_api/contexts/records/domain/record.py`——放开 `attachment_refs`
- `src/aim_api/contexts/records/application/ports.py`——附件仓储端口、存储端口
- `src/aim_api/contexts/records/application/commands/create_record.py`——挂附件
- `src/aim_api/contexts/records/application/commands/purge_attachments.py`（新建）——清理用例
- `src/aim_api/contexts/records/adapters/outbound/persistence/models.py`、`repositories.py`——附件表与仓储
- `src/aim_api/contexts/records/adapters/outbound/storage.py`（新建）——本地磁盘存储
- `src/aim_api/contexts/records/adapters/inbound/http/attachments_router.py`（新建）——上传、查看接口
- `src/aim_api/contexts/agent_access/adapters/inbound/http/router.py`——内部「新建记录」带附件编号
- `src/aim_api/contexts/identity/application/commands/purge_expired_deletions.py`——注销时清附件行
- `src/aim_api/platform/config/settings.py`、`src/aim_api/bootstrap.py`
- `migrations/versions/0010_attachments.py`（新建）
- `scripts/purge_orphan_attachments.py`（新建）
- 测试：`tests/conftest.py`、`tests/integration/records/test_attachments.py`（新建）、`tests/integration/records/test_attachment_purge.py`（新建）、`tests/integration/agent_access/test_authoring_tools.py`

**services/agent**
- `Dockerfile`、`agent/channels/eve.ts`、`agent/lib/model-config.ts`、`agent/tools/create_record.ts`、`agent/instructions.md`
- 测试：`tests/model-config.test.ts`、`tests/tools/authoring.test.ts`

**infrastructure**
- `compose/compose.yaml`（附件数据卷、模型名默认值）、`deploy/aim-backup.sh`、`deploy/README.md`

**apps/agent-web**
- `src/imageAttachments.ts`（新建）——压缩尺寸计算、每轮图片上下文、附件适配器
- `src/entry.ts`——每轮上下文合并页面与图片
- `src/App.tsx`、`src/thread/Composer.tsx`（新建）、`src/thread/MessageImages.tsx`（新建）、`src/tools/CreateRecord.tsx`、`src/styles.css`
- 测试：`src/imageAttachments.test.ts`（新建）、`src/entry.test.ts`

**apps/ios**
- `AimApp/Resources/Info.plist`——相机权限说明
- `AimApp/Features/Records/RecordDetailView.swift`——图片区、全屏查看、图片加载
- 测试：`AimApp/Tests/RecordStoreTests.swift`

---

### Task 1：附件表、领域与本地存储

**Files:**
- Create: `services/api/src/aim_api/contexts/records/domain/attachment.py`
- Modify: `services/api/src/aim_api/contexts/records/domain/errors.py`
- Modify: `services/api/src/aim_api/contexts/records/application/ports.py`
- Modify: `services/api/src/aim_api/contexts/records/adapters/outbound/persistence/models.py`
- Modify: `services/api/src/aim_api/contexts/records/adapters/outbound/persistence/repositories.py`
- Create: `services/api/src/aim_api/contexts/records/adapters/outbound/storage.py`
- Modify: `services/api/src/aim_api/platform/config/settings.py`
- Create: `services/api/migrations/versions/0010_attachments.py`
- Modify: `services/api/tests/conftest.py`
- Test: `services/api/tests/domain/records/test_attachment.py`（新建）

**Interfaces:**
- Produces:
  - `Attachment.upload(*, attachment_id, family_id, pregnancy_id, uploaded_by, media_type, byte_size, now=None) -> Attachment`，类型或大小不对抛 `AttachmentRejected(kind)`，`kind ∈ {"too_large", "bad_type"}`
  - `Attachment.attach_to(record_id: UUID) -> None`，已挂靠抛 `AttachmentUnavailable`
  - 常量 `MAX_ATTACHMENT_BYTES = 2 * 1024 * 1024`、`ALLOWED_MEDIA_TYPES`、`MAX_ATTACHMENTS_PER_RECORD = 4`
  - `SqlAlchemyAttachmentRepository(session)`：`add(att)`、`get(id) -> Attachment | None`、`attach(ids, record_id)`
  - `LocalAttachmentStorage(root)`：`save(id, data: bytes)`、`read(id) -> bytes | None`、`delete(id)`、`list_files() -> list[tuple[UUID, float]]`（编号与修改时间）
  - `SqlAlchemyRecordsUnitOfWork.attachments`
  - `Settings.attachments_root`（环境变量 `AIM_ATTACHMENTS_ROOT`）

- [ ] **Step 1: 写失败测试**

`services/api/tests/domain/records/test_attachment.py`：

```python
from __future__ import annotations

from uuid import uuid4

import pytest

from aim_api.contexts.records.domain.attachment import MAX_ATTACHMENT_BYTES, Attachment
from aim_api.contexts.records.domain.errors import AttachmentRejected, AttachmentUnavailable


def _upload(**overrides):
    values = dict(
        attachment_id=uuid4(),
        family_id=uuid4(),
        pregnancy_id=uuid4(),
        uploaded_by=uuid4(),
        media_type="image/jpeg",
        byte_size=1000,
    )
    values.update(overrides)
    return Attachment.upload(**values)


def test_accepts_a_small_jpeg() -> None:
    attachment = _upload()
    assert attachment.record_id is None


def test_rejects_other_types() -> None:
    with pytest.raises(AttachmentRejected) as caught:
        _upload(media_type="application/pdf")
    assert caught.value.kind == "bad_type"


def test_rejects_anything_over_two_megabytes() -> None:
    with pytest.raises(AttachmentRejected) as caught:
        _upload(byte_size=MAX_ATTACHMENT_BYTES + 1)
    assert caught.value.kind == "too_large"


def test_can_only_be_attached_once() -> None:
    attachment = _upload()
    attachment.attach_to(uuid4())
    with pytest.raises(AttachmentUnavailable):
        attachment.attach_to(uuid4())
```

- [ ] **Step 2: 运行确认失败**

Run: `cd services/api && PYTHONPATH=src python3 -m pytest tests/domain/records/test_attachment.py -q`
Expected: FAIL，`ModuleNotFoundError: ...attachment`

- [ ] **Step 3: 领域与错误**

`errors.py` 末尾追加：

```python
class AttachmentRejected(RecordsDomainError):
    """上传的附件类型或大小不合规。kind 用来决定返回 413 还是 415。"""

    def __init__(self, kind: str, message: str) -> None:
        super().__init__(message)
        self.kind = kind


class AttachmentUnavailable(RecordsDomainError):
    """附件不存在、不属于本家庭，或已经挂在别的记录上。"""
```

`domain/attachment.py`：

```python
from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID

from aim_api.contexts.records.domain.errors import AttachmentRejected, AttachmentUnavailable

#: 网页端会把图片压成 JPEG 再传；另两种留给以后的入口。
ALLOWED_MEDIA_TYPES = frozenset({"image/jpeg", "image/png", "image/webp"})
MAX_ATTACHMENT_BYTES = 2 * 1024 * 1024
MAX_ATTACHMENTS_PER_RECORD = 4


@dataclass(slots=True)
class Attachment:
    id: UUID
    family_id: UUID
    pregnancy_id: UUID
    uploaded_by: UUID | None
    media_type: str
    byte_size: int
    record_id: UUID | None
    created_at: datetime

    @classmethod
    def upload(
        cls,
        *,
        attachment_id: UUID,
        family_id: UUID,
        pregnancy_id: UUID,
        uploaded_by: UUID,
        media_type: str,
        byte_size: int,
        now: datetime | None = None,
    ) -> Attachment:
        if media_type not in ALLOWED_MEDIA_TYPES:
            raise AttachmentRejected("bad_type", "只支持 JPEG、PNG、WebP 图片")
        if byte_size <= 0 or byte_size > MAX_ATTACHMENT_BYTES:
            raise AttachmentRejected("too_large", "图片不能超过 2 MB")
        return cls(
            id=attachment_id,
            family_id=family_id,
            pregnancy_id=pregnancy_id,
            uploaded_by=uploaded_by,
            media_type=media_type,
            byte_size=byte_size,
            record_id=None,
            created_at=now or datetime.now(UTC),
        )

    def attach_to(self, record_id: UUID) -> None:
        if self.record_id is not None:
            raise AttachmentUnavailable("这张图片已经挂在别的记录上了")
        self.record_id = record_id
```

- [ ] **Step 4: 端口、持久化模型、仓储、存储、配置**

`application/ports.py` 追加（并在 `RecordsUnitOfWork` 里加 `attachments: AttachmentRepositoryPort`）：

```python
class AttachmentRepositoryPort(Protocol):
    async def add(self, attachment: Attachment) -> None: ...

    async def get(self, attachment_id: UUID) -> Attachment | None: ...

    async def attach(self, attachment_ids: list[UUID], record_id: UUID) -> None: ...


class AttachmentStoragePort(Protocol):
    def save(self, attachment_id: UUID, data: bytes) -> None: ...

    def read(self, attachment_id: UUID) -> bytes | None: ...

    def delete(self, attachment_id: UUID) -> None: ...

    def list_files(self) -> list[tuple[UUID, float]]: ...
```

（文件头 import `Attachment` 自 `aim_api.contexts.records.domain.attachment`。）

`persistence/models.py` 追加：

```python
class AttachmentModel(Base):
    """与 records 表一致不设外键：注销清理按表逐个显式删除。"""

    __tablename__ = "attachments"
    __table_args__ = (
        Index("ix_attachments_record", "record_id"),
        Index("ix_attachments_family", "family_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    family_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    pregnancy_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    uploaded_by: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
    media_type: Mapped[str] = mapped_column(String(40), nullable=False)
    byte_size: Mapped[int] = mapped_column(Integer, nullable=False)
    record_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
```

（import 补 `Integer`。）

`persistence/repositories.py` 追加仓储，并在 `SqlAlchemyRecordsUnitOfWork.__init__` 里加 `self.attachments = SqlAlchemyAttachmentRepository(session)`：

```python
class SqlAlchemyAttachmentRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def add(self, attachment: Attachment) -> None:
        self.session.add(
            AttachmentModel(
                id=attachment.id,
                family_id=attachment.family_id,
                pregnancy_id=attachment.pregnancy_id,
                uploaded_by=attachment.uploaded_by,
                media_type=attachment.media_type,
                byte_size=attachment.byte_size,
                record_id=attachment.record_id,
                created_at=attachment.created_at,
            )
        )

    async def get(self, attachment_id: UUID) -> Attachment | None:
        model = await self.session.get(AttachmentModel, attachment_id)
        if model is None:
            return None
        return Attachment(
            id=model.id,
            family_id=model.family_id,
            pregnancy_id=model.pregnancy_id,
            uploaded_by=model.uploaded_by,
            media_type=model.media_type,
            byte_size=model.byte_size,
            record_id=model.record_id,
            created_at=model.created_at,
        )

    async def attach(self, attachment_ids: list[UUID], record_id: UUID) -> None:
        await self.session.execute(
            update(AttachmentModel)
            .where(AttachmentModel.id.in_(attachment_ids), AttachmentModel.record_id.is_(None))
            .values(record_id=record_id)
        )
```

（import 补 `update`、`AttachmentModel`、`Attachment`。）

`adapters/outbound/storage.py`：

```python
"""附件文件的本地磁盘存储。

按编号前两位分目录，避免单个目录里文件过多。以后换对象存储时只替换这个类。
"""

from __future__ import annotations

import os
from pathlib import Path
from uuid import UUID


class LocalAttachmentStorage:
    def __init__(self, root: str | Path) -> None:
        self.root = Path(root)

    def _path(self, attachment_id: UUID) -> Path:
        text = str(attachment_id)
        return self.root / text[:2] / text

    def save(self, attachment_id: UUID, data: bytes) -> None:
        path = self._path(attachment_id)
        path.parent.mkdir(parents=True, exist_ok=True)
        # 先写临时文件再改名：写到一半进程被杀，也不会留下半张图。
        temporary = path.with_suffix(".part")
        temporary.write_bytes(data)
        os.replace(temporary, path)

    def read(self, attachment_id: UUID) -> bytes | None:
        path = self._path(attachment_id)
        return path.read_bytes() if path.exists() else None

    def delete(self, attachment_id: UUID) -> None:
        self._path(attachment_id).unlink(missing_ok=True)

    def list_files(self) -> list[tuple[UUID, float]]:
        found: list[tuple[UUID, float]] = []
        if not self.root.exists():
            return found
        for path in self.root.glob("*/*"):
            if path.suffix == ".part":
                continue
            try:
                found.append((UUID(path.name), path.stat().st_mtime))
            except ValueError:
                continue
        return found
```

`settings.py` 的 `Settings` 里加：

```python
    attachments_root: str = Field(default="var/attachments", validation_alias="AIM_ATTACHMENTS_ROOT")
```

`migrations/versions/0010_attachments.py`：

```python
"""Store uploaded images and link them to records."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0010_attachments"
down_revision = "0009_tool_invocation_scope"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "attachments",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("family_id", sa.Uuid(), nullable=False),
        sa.Column("pregnancy_id", sa.Uuid(), nullable=False),
        sa.Column("uploaded_by", sa.Uuid(), nullable=True),
        sa.Column("media_type", sa.String(40), nullable=False),
        sa.Column("byte_size", sa.Integer(), nullable=False),
        sa.Column("record_id", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_attachments_record", "attachments", ["record_id"])
    op.create_index("ix_attachments_family", "attachments", ["family_id"])


def downgrade() -> None:
    op.drop_index("ix_attachments_family", table_name="attachments")
    op.drop_index("ix_attachments_record", table_name="attachments")
    op.drop_table("attachments")
```

`tests/conftest.py` 追加一个会话级夹具，让测试把图片写进临时目录：

```python
@pytest.fixture(scope="session", autouse=True)
def attachments_root(tmp_path_factory) -> Iterator[str]:
    root = tmp_path_factory.mktemp("attachments")
    previous = os.environ.get("AIM_ATTACHMENTS_ROOT")
    os.environ["AIM_ATTACHMENTS_ROOT"] = str(root)
    get_settings.cache_clear()
    try:
        yield str(root)
    finally:
        if previous is None:
            os.environ.pop("AIM_ATTACHMENTS_ROOT", None)
        else:
            os.environ["AIM_ATTACHMENTS_ROOT"] = previous
        get_settings.cache_clear()
```

- [ ] **Step 5: 运行确认通过**

Run: `cd services/api && PYTHONPATH=src python3 -m pytest tests/domain/records/test_attachment.py tests/architecture -q`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add services/api
git commit -m "feat(api): 附件表、领域校验与本地磁盘存储"
```

---

### Task 2：上传与查看接口

**Files:**
- Create: `services/api/src/aim_api/contexts/records/adapters/inbound/http/attachments_router.py`
- Modify: `services/api/src/aim_api/bootstrap.py`
- Modify: `contracts/public-api/openapi.json`（生成）
- Test: `services/api/tests/integration/records/test_attachments.py`（新建）

**Interfaces:**
- Consumes: Task 1 的 `Attachment.upload`、`SqlAlchemyRecordsUnitOfWork.attachments`、`LocalAttachmentStorage`、`Settings.attachments_root`
- Produces:
  - `POST /api/v1/pregnancies/{pregnancy_id}/attachments`，请求体为图片原始字节，`Content-Type` 为图片类型 → `201 {id, media_type, byte_size}`；超 2 MB → 413；类型不对 → 415；非成员 → 403
  - `GET /api/v1/attachments/{attachment_id}` → 图片字节；非本家庭成员或不存在 → 404
  - `attachment_storage(request) -> LocalAttachmentStorage`（供 Task 3、4 复用）

- [ ] **Step 1: 写失败测试**

`services/api/tests/integration/records/test_attachments.py`：

```python
from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings

JPEG = b"\xff\xd8\xff\xe0" + b"0" * 2000


def _phone(account_id: str) -> str:
    return "137" + str(int(UUID(account_id)) % 10**8).zfill(8)


def _family(client: TestClient):
    """返回 (请求头, 孕期编号, 账号编号, 家庭编号)。"""
    account_id = str(uuid4())
    token = issue_session_token(UUID(account_id), _phone(account_id), get_settings().auth_secret)
    headers = {"Authorization": f"Bearer {token}"}
    family = client.post(
        "/api/v1/families", headers=headers, json={"name": "附件家庭", "role": "mother"}
    ).json()
    pregnancy = client.post(
        f"/api/v1/families/{family['id']}/pregnancies", headers=headers, json={"due_date": "2027-01-12"}
    ).json()
    return headers, pregnancy["id"], account_id, family["id"]


def _upload(client, headers, pregnancy_id, body=JPEG, media_type="image/jpeg"):
    return client.post(
        f"/api/v1/pregnancies/{pregnancy_id}/attachments",
        headers={**headers, "Content-Type": media_type},
        content=body,
    )


def test_upload_then_read_back_the_same_bytes() -> None:
    with TestClient(create_app()) as client:
        headers, pregnancy_id, *_ = _family(client)
        uploaded = _upload(client, headers, pregnancy_id)
        assert uploaded.status_code == 201, uploaded.text
        body = uploaded.json()
        assert body["media_type"] == "image/jpeg" and body["byte_size"] == len(JPEG)

        fetched = client.get(f"/api/v1/attachments/{body['id']}", headers=headers)
        assert fetched.status_code == 200
        assert fetched.content == JPEG
        assert fetched.headers["content-type"] == "image/jpeg"


def test_rejects_wrong_type_and_oversize() -> None:
    with TestClient(create_app()) as client:
        headers, pregnancy_id, *_ = _family(client)
        assert _upload(client, headers, pregnancy_id, b"%PDF", "application/pdf").status_code == 415
        huge = b"0" * (2 * 1024 * 1024 + 1)
        assert _upload(client, headers, pregnancy_id, huge).status_code == 413


def test_other_families_cannot_see_it() -> None:
    with TestClient(create_app()) as client:
        headers, pregnancy_id, *_ = _family(client)
        other_headers, *_ = _family(client)
        attachment_id = _upload(client, headers, pregnancy_id).json()["id"]
        assert client.get(f"/api/v1/attachments/{attachment_id}", headers=other_headers).status_code == 404
        assert client.get(f"/api/v1/attachments/{uuid4()}", headers=headers).status_code == 404


def test_cannot_upload_into_someone_elses_pregnancy() -> None:
    with TestClient(create_app()) as client:
        _, pregnancy_id, *_ = _family(client)
        other_headers, *_ = _family(client)
        assert _upload(client, other_headers, pregnancy_id).status_code == 403
```

- [ ] **Step 2: 运行确认失败**

Run: `cd services/api && PYTHONPATH=src python3 -m pytest tests/integration/records/test_attachments.py -q`
Expected: FAIL（404，路由不存在）

- [ ] **Step 3: 实现接口**

`attachments_router.py`：

```python
"""图片附件的上传与查看。

上传收图片原始字节（不用表单），网页端已经压缩过；查看只对附件所属家庭的在籍成员开放，
其他人一律 404——既不暴露内容，也不暴露「这个编号存在」。
"""

from __future__ import annotations

from uuid import UUID, uuid4

from fastapi import APIRouter, Request, Response
from pydantic import BaseModel

from aim_api.contexts.records.adapters.outbound.persistence.repositories import (
    SqlAlchemyRecordsUnitOfWork,
)
from aim_api.contexts.records.adapters.outbound.storage import LocalAttachmentStorage
from aim_api.contexts.records.domain.attachment import MAX_ATTACHMENT_BYTES, Attachment
from aim_api.contexts.records.domain.errors import AttachmentRejected
from aim_api.platform.auth.context import authenticate_active
from aim_api.platform.http.errors import ApiError, ForbiddenError, NotFoundError

router = APIRouter(tags=["attachments"])


class PayloadTooLarge(ApiError):
    status_code = 413
    code = "attachment.too_large"


class UnsupportedMediaType(ApiError):
    status_code = 415
    code = "attachment.bad_type"


class AttachmentResponse(BaseModel):
    id: UUID
    media_type: str
    byte_size: int


def attachment_storage(request: Request) -> LocalAttachmentStorage:
    return LocalAttachmentStorage(request.app.state.settings.attachments_root)


@router.post(
    "/api/v1/pregnancies/{pregnancy_id}/attachments",
    response_model=AttachmentResponse,
    status_code=201,
)
async def upload_attachment(pregnancy_id: UUID, request: Request) -> AttachmentResponse:
    actor = await authenticate_active(request)
    declared = int(request.headers.get("content-length") or 0)
    if declared > MAX_ATTACHMENT_BYTES:
        raise PayloadTooLarge("图片不能超过 2 MB")
    data = await request.body()
    media_type = (request.headers.get("content-type") or "").split(";")[0].strip()

    async with request.app.state.database.session() as session:
        uow = SqlAlchemyRecordsUnitOfWork(session)
        pregnancy = await uow.pregnancy_ownership.get_pregnancy(pregnancy_id)
        if pregnancy is None or not await uow.family_membership.is_active_member(
            pregnancy.family_id, actor.account_id
        ):
            raise ForbiddenError("不能往这段孕期上传图片")
        try:
            attachment = Attachment.upload(
                attachment_id=uuid4(),
                family_id=pregnancy.family_id,
                pregnancy_id=pregnancy_id,
                uploaded_by=actor.account_id,
                media_type=media_type,
                byte_size=len(data),
            )
        except AttachmentRejected as error:
            if error.kind == "too_large":
                raise PayloadTooLarge(str(error)) from error
            raise UnsupportedMediaType(str(error)) from error

        storage = attachment_storage(request)
        storage.save(attachment.id, data)
        try:
            await uow.attachments.add(attachment)
            await uow.commit()
        except Exception:
            # 行没写进去，文件就不该留着。
            storage.delete(attachment.id)
            raise
    return AttachmentResponse(
        id=attachment.id, media_type=attachment.media_type, byte_size=attachment.byte_size
    )


@router.get("/api/v1/attachments/{attachment_id}")
async def read_attachment(attachment_id: UUID, request: Request) -> Response:
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        uow = SqlAlchemyRecordsUnitOfWork(session)
        attachment = await uow.attachments.get(attachment_id)
        if attachment is None or not await uow.family_membership.is_active_member(
            attachment.family_id, actor.account_id
        ):
            raise NotFoundError("没有找到这张图片")
    data = attachment_storage(request).read(attachment_id)
    if data is None:
        raise NotFoundError("没有找到这张图片")
    # 编号对应的内容永不改变，可以长期缓存；private 保证只缓存在本人设备上。
    return Response(
        content=data,
        media_type=attachment.media_type,
        headers={"Cache-Control": "private, max-age=31536000, immutable"},
    )
```

`bootstrap.py`：import `router as attachments_router` 自 `...records.adapters.inbound.http.attachments_router`，在 `app.include_router(agent_operations_router)` 下一行加 `app.include_router(attachments_router)`。确认 `create_app` 里 `app.state.settings` 已设置（`resolve-session` 已在用 `request.app.state.settings`）。

- [ ] **Step 4: 运行确认通过，重新生成契约**

```bash
cd services/api && PYTHONPATH=src python3 -m pytest tests/integration/records/test_attachments.py -q
cd ../.. && make -C services/api contracts && make -C services/api test
```

Expected: 全部 PASS；`contracts/public-api/openapi.json` 多出两个路径。

- [ ] **Step 5: 提交**

```bash
git add services/api contracts
git commit -m "feat(api): 图片附件的上传与查看接口，只对本家庭成员可见"
```

---

### Task 3：新建记录时挂上附件

**Files:**
- Modify: `services/api/src/aim_api/contexts/records/domain/record.py`
- Modify: `services/api/src/aim_api/contexts/records/application/commands/create_record.py`
- Modify: `services/api/src/aim_api/contexts/records/application/commands/update_record.py`
- Modify: `services/api/src/aim_api/contexts/records/application/commands/save_record.py`
- Modify: `services/api/src/aim_api/contexts/records/adapters/outbound/persistence/repositories.py`
- Modify: `services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/router.py`
- Test: `services/api/tests/integration/records/test_attachments.py`

**Interfaces:**
- Consumes: Task 1、2
- Produces:
  - `CreateRecordCommand.attachment_ids: tuple[UUID, ...] = ()`
  - 内部工具「新建记录」请求体增加 `attachment_ids: list[UUID]`（最多 4 个），结果 `data` 增加 `attachment_count`

- [ ] **Step 1: 写失败测试**

在 `test_attachments.py` 末尾追加：

```python
GATEWAY = "/internal/agent-tools"


def _agent(scope, call_id: str) -> dict[str, str]:
    _, pregnancy_id, account_id, family_id = scope
    return {
        "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
        "Actor-Account-Id": account_id,
        "Family-Id": family_id,
        "Pregnancy-Id": pregnancy_id,
        "Eve-Session-Id": f"eve-attach-{account_id}",
        "Idempotency-Key": call_id,
    }


def test_agent_attaches_the_report_photo_to_the_checkup_record() -> None:
    with TestClient(create_app()) as client:
        scope = _family(client)
        headers, pregnancy_id, *_ = scope
        attachment_id = _upload(client, headers, pregnancy_id).json()["id"]

        created = client.post(
            f"{GATEWAY}/create-record",
            headers=_agent(scope, "r1"),
            json={
                "record_type": "checkup",
                "structured_data": {
                    "hospital": "杭州市妇产科医院",
                    "exam_items": "",
                    "result": "",
                    "doctor_advice": "注意补铁",
                    "metrics": {"hemoglobin": 112},
                },
                "attachment_ids": [attachment_id],
            },
        )
        assert created.status_code == 200, created.text
        assert created.json()["data"]["attachment_count"] == 1
        record_id = created.json()["data"]["record_id"]

        records = client.get(f"/api/v1/pregnancies/{pregnancy_id}/records", headers=headers).json()
        record = next(r for r in records["records"] if r["id"] == record_id)
        assert record["attachment_refs"] == [attachment_id]


def test_a_photo_cannot_be_attached_twice_or_across_families() -> None:
    with TestClient(create_app()) as client:
        scope = _family(client)
        headers, pregnancy_id, *_ = scope
        other_headers, other_pregnancy, *_ = _family(client)
        mine = _upload(client, headers, pregnancy_id).json()["id"]
        theirs = _upload(client, other_headers, other_pregnancy).json()["id"]
        agent = _agent(scope, "r2")
        note = {"record_type": "note", "content": "存档"}

        first = client.post(f"{GATEWAY}/create-record", headers=agent, json={**note, "attachment_ids": [mine]})
        assert first.status_code == 200, first.text
        again = client.post(
            f"{GATEWAY}/create-record",
            headers={**agent, "Idempotency-Key": "r3"},
            json={**note, "attachment_ids": [mine]},
        )
        assert again.status_code == 409
        assert "已经挂在别的记录上" in again.json()["error"]["message"]
        foreign = client.post(
            f"{GATEWAY}/create-record",
            headers={**agent, "Idempotency-Key": "r4"},
            json={**note, "attachment_ids": [theirs]},
        )
        assert foreign.status_code == 409
        assert "找不到这张图片" in foreign.json()["error"]["message"]
```

- [ ] **Step 2: 运行确认失败**

Run: `cd services/api && PYTHONPATH=src python3 -m pytest tests/integration/records/test_attachments.py -q`
Expected: 新增两条 FAIL（422 或附件被拒）

- [ ] **Step 3: 放开领域限制并在命令里挂附件**

`domain/record.py`：删除 `Record.create` 里 `if attachment_refs: raise ...` 两行；删除方法 `assert_attachment_refs_reserved`。在 `repositories.py`（两处）、`update_record.py`、`save_record.py` 里删掉对 `assert_attachment_refs_reserved()` 的调用。

`create_record.py`：

```python
@dataclass(frozen=True, slots=True)
class CreateRecordCommand:
    ...
    now: datetime | None = None
    #: 要挂到这条记录上的图片编号。必须属于同一家庭、尚未挂到别的记录。
    attachment_ids: tuple[UUID, ...] = ()


async def execute(command: CreateRecordCommand, uow: RecordsUnitOfWork) -> Record:
    ...  # 原有的孕期、成员校验不变
    await _check_attachments(command, uow)
    record = Record.create(
        ...,
        attachment_refs=[str(attachment_id) for attachment_id in command.attachment_ids],
        now=command.now,
    )
    await uow.repository.add_record(record)
    if command.attachment_ids:
        await uow.attachments.attach(list(command.attachment_ids), record.id)
    await uow.commit()
    return record


async def _check_attachments(command: CreateRecordCommand, uow: RecordsUnitOfWork) -> None:
    if len(command.attachment_ids) > MAX_ATTACHMENTS_PER_RECORD:
        raise RecordValidationError("一条记录最多挂 4 张图片")
    for attachment_id in command.attachment_ids:
        attachment = await uow.attachments.get(attachment_id)
        # 别的家庭的图片与不存在的图片同一说法：不暴露编号是否存在。
        if attachment is None or attachment.family_id != command.family_id:
            raise RecordValidationError("找不到这张图片，请让用户重新发一次")
        if attachment.record_id is not None:
            raise RecordValidationError("这张图片已经挂在别的记录上了")
```

（import 补 `MAX_ATTACHMENTS_PER_RECORD`、`RecordValidationError`。）

内部路由 `router.py`：

```python
class CreateRecordRequest(BaseModel):
    record_type: RecordType
    structured_data: dict[str, Any] = Field(default_factory=dict)
    title: str | None = None
    content: str | None = None
    occurred_at: datetime | None = None
    attachment_ids: list[UUID] = Field(default_factory=list, max_length=4)
```

`_create_record` 给 `CreateRecordCommand` 加 `attachment_ids=tuple(UUID(i) for i in body.get("attachment_ids") or [])`，返回值改为：

```python
    return (
        {"record_id": str(record.id), "attachment_count": len(record.attachment_refs)},
        "已记录" + (f"，附上 {len(record.attachment_refs)} 张图" if record.attachment_refs else ""),
    )
```

- [ ] **Step 4: 运行确认通过**

Run: `cd services/api && PYTHONPATH=src python3 -m pytest tests/integration/records tests/integration/agent_access tests/domain/records -q && cd ../.. && make -C services/api test`
Expected: 全部 PASS

- [ ] **Step 5: 提交**

```bash
git add services/api
git commit -m "feat(api): 新建记录可挂图片，校验同家庭且未挂到别处"
```

---

### Task 4：清理、注销、备份与数据卷

**Files:**
- Create: `services/api/src/aim_api/contexts/records/application/commands/purge_attachments.py`
- Create: `services/api/scripts/purge_orphan_attachments.py`
- Modify: `services/api/src/aim_api/contexts/identity/application/commands/purge_expired_deletions.py`
- Modify: `infrastructure/compose/compose.yaml`
- Modify: `infrastructure/deploy/aim-backup.sh`
- Modify: `infrastructure/deploy/README.md`
- Test: `services/api/tests/integration/records/test_attachment_purge.py`（新建）

**Interfaces:**
- Consumes: Task 1 的 `LocalAttachmentStorage`、`AttachmentModel`
- Produces: `purge_attachments.execute(session, storage, *, now, dry_run=False) -> PurgeAttachmentsSummary(rows_deleted, files_deleted)`

- [ ] **Step 1: 写失败测试**

`test_attachment_purge.py`：

```python
from __future__ import annotations

import asyncio
import os
from datetime import UTC, datetime, timedelta
from uuid import uuid4

from aim_api.contexts.records.adapters.outbound.storage import LocalAttachmentStorage
from aim_api.contexts.records.application.commands import purge_attachments
from aim_api.platform.config.settings import get_settings
from aim_api.platform.database.session import create_database
from sqlalchemy import text

NOW = datetime(2026, 12, 1, tzinfo=UTC)


async def _seed(session, *, attachment_id, created_at, record_id=None):
    await session.execute(
        text(
            "INSERT INTO attachments (id, family_id, pregnancy_id, uploaded_by, media_type, "
            "byte_size, record_id, created_at) VALUES (:id, :f, :p, NULL, 'image/jpeg', 10, :r, :c)"
        ),
        {"id": attachment_id, "f": uuid4(), "p": uuid4(), "r": record_id, "c": created_at},
    )


async def _seed_record(session, *, record_id, deleted_at):
    await session.execute(
        text(
            "INSERT INTO records (id, pregnancy_id, family_id, author_account_id, record_type, "
            "occurred_at, visibility, structured_data, attachment_refs, created_at, updated_at, "
            "deleted_at) VALUES (:id, :p, :f, :a, 'note', :t, 'family', '{}', '[]', :t, :t, :d)"
        ),
        {"id": record_id, "p": uuid4(), "f": uuid4(), "a": uuid4(), "t": NOW, "d": deleted_at},
    )


def test_purges_old_orphans_long_deleted_records_and_stray_files(tmp_path) -> None:
    storage = LocalAttachmentStorage(tmp_path)
    old_orphan, fresh_orphan, on_deleted, on_live = (uuid4() for _ in range(4))
    stray = uuid4()
    long_deleted_record, live_record = uuid4(), uuid4()

    async def run():
        database = create_database(get_settings().database_url)
        async with database.session() as session:
            await _seed_record(session, record_id=long_deleted_record, deleted_at=NOW - timedelta(days=31))
            await _seed_record(session, record_id=live_record, deleted_at=None)
            await _seed(session, attachment_id=old_orphan, created_at=NOW - timedelta(days=91))
            await _seed(session, attachment_id=fresh_orphan, created_at=NOW - timedelta(days=10))
            await _seed(session, attachment_id=on_deleted, created_at=NOW - timedelta(days=40), record_id=long_deleted_record)
            await _seed(session, attachment_id=on_live, created_at=NOW - timedelta(days=200), record_id=live_record)
            await session.commit()
        for attachment_id in (old_orphan, fresh_orphan, on_deleted, on_live, stray):
            storage.save(attachment_id, b"x")
        old = (NOW - timedelta(days=2)).timestamp()
        os.utime(storage._path(stray), (old, old))

        async with database.session() as session:
            return await purge_attachments.execute(session, storage, now=NOW)

    summary = asyncio.run(run())
    remaining = {attachment_id for attachment_id, _ in storage.list_files()}
    assert remaining == {fresh_orphan, on_live}
    assert summary.rows_deleted == 2
    assert summary.files_deleted == 3
```

- [ ] **Step 2: 运行确认失败**

Run: `cd services/api && PYTHONPATH=src python3 -m pytest tests/integration/records/test_attachment_purge.py -q`
Expected: FAIL（模块不存在）

- [ ] **Step 3: 实现清理用例与脚本**

`purge_attachments.py`：

```python
"""清理不再需要的图片附件。

三类：没挂到任何记录、上传超过 90 天的；所挂记录已删除超过 30 天的（记录是软删除，
30 天内撤销还能连图一起回来）；数据库里已经没有对应行的孤儿文件（注销清理只删行，
文件在这里统一扫掉）。孤儿文件只删修改时间超过 1 小时的，避免误删正在上传的图。
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from aim_api.contexts.records.application.ports import AttachmentStoragePort

ORPHAN_RETENTION = timedelta(days=90)
DELETED_RECORD_RETENTION = timedelta(days=30)
STRAY_FILE_GRACE = timedelta(hours=1)


@dataclass(frozen=True, slots=True)
class PurgeAttachmentsSummary:
    rows_deleted: int
    files_deleted: int


async def execute(
    session: AsyncSession, storage: AttachmentStoragePort, *, now: datetime, dry_run: bool = False
) -> PurgeAttachmentsSummary:
    expired = [
        UUID(str(value))
        for value in (
            await session.execute(
                text(
                    "SELECT a.id FROM attachments a "
                    "LEFT JOIN records r ON r.id = a.record_id "
                    "WHERE (a.record_id IS NULL AND a.created_at < :orphan_cutoff) "
                    "OR (r.deleted_at IS NOT NULL AND r.deleted_at < :deleted_cutoff)"
                ),
                {
                    "orphan_cutoff": now - ORPHAN_RETENTION,
                    "deleted_cutoff": now - DELETED_RECORD_RETENTION,
                },
            )
        ).scalars()
    ]
    known = {
        UUID(str(value))
        for value in (await session.execute(text("SELECT id FROM attachments"))).scalars()
    }
    grace_cutoff = (now - STRAY_FILE_GRACE).timestamp()
    stray = [
        attachment_id
        for attachment_id, modified_at in storage.list_files()
        if attachment_id not in known and modified_at < grace_cutoff
    ]
    if dry_run:
        await session.rollback()
        return PurgeAttachmentsSummary(rows_deleted=len(expired), files_deleted=len(expired) + len(stray))

    if expired:
        await session.execute(
            text("DELETE FROM attachments WHERE id = ANY(:ids)"), {"ids": expired}
        )
    await session.commit()
    for attachment_id in [*expired, *stray]:
        storage.delete(attachment_id)
    return PurgeAttachmentsSummary(rows_deleted=len(expired), files_deleted=len(expired) + len(stray))
```

`scripts/purge_orphan_attachments.py`（结构同 `purge_deleted_accounts.py`）：

```python
#!/usr/bin/env python3
"""清理过期与无主的图片附件。每天由 crontab 跑一次（见 infrastructure/deploy/README.md）。

    docker exec -i aim-api-1 python scripts/purge_orphan_attachments.py
    docker exec -i aim-api-1 python scripts/purge_orphan_attachments.py --dry-run
"""

from __future__ import annotations

import asyncio
import sys
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from aim_api.contexts.records.adapters.outbound.storage import LocalAttachmentStorage  # noqa: E402
from aim_api.contexts.records.application.commands import purge_attachments  # noqa: E402
from aim_api.platform.config.settings import get_settings  # noqa: E402
from aim_api.platform.database.session import create_database  # noqa: E402


async def run(dry_run: bool) -> int:
    settings = get_settings()
    database = create_database(settings.database_url)
    storage = LocalAttachmentStorage(settings.attachments_root)
    async with database.session() as session:
        summary = await purge_attachments.execute(
            session, storage, now=datetime.now(UTC), dry_run=dry_run
        )
    prefix = "[dry-run] " if dry_run else ""
    print(f"{prefix}删除附件记录 {summary.rows_deleted} 条，删除文件 {summary.files_deleted} 个")
    return 0


def main() -> int:
    return asyncio.run(run("--dry-run" in sys.argv[1:]))


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: 注销时清附件行**

`purge_expired_deletions.py` 的 `_purge_one`：
1. 在删私密记录那句**之前**加：

```python
    # 私密记录上挂的图片：行在这里删，文件由每天的附件清理扫掉。
    await session.execute(
        text(
            "DELETE FROM attachments WHERE record_id IN (SELECT id FROM records "
            "WHERE author_account_id = :id AND visibility = 'private')"
        ),
        {"id": account_id},
    )
    await session.execute(
        text("UPDATE attachments SET uploaded_by = NULL WHERE uploaded_by = :id"), {"id": account_id}
    )
```

2. 在「唯一成员」分支 `DELETE FROM records WHERE family_id = :family` **之前**加：

```python
            await session.execute(
                text("DELETE FROM attachments WHERE family_id = :family"), {"family": family_id}
            )
```

在既有的注销测试文件里（`grep -rln purge_expired_deletions services/api/tests`）追加一条：唯一成员的家庭注销后 `attachments` 里该家庭的行为 0。

- [ ] **Step 5: 数据卷、备份、部署文档**

`compose.yaml` 的 `api` 服务：`environment` 加 `AIM_ATTACHMENTS_ROOT: /data/attachments`；加

```yaml
    volumes:
      - attachments:/data/attachments
```

顶层 `volumes:` 加 `attachments:`（Compose 项目名为 `aim`，实际卷名 `aim_attachments`）。

`aim-backup.sh` 在数据库备份之后加：

```bash
docker run --rm -v aim_attachments:/data:ro -v "$DIR":/backup alpine \
  tar -czf "/backup/aim-attachments-$STAMP.tar.gz" -C /data .
find "$DIR" -name 'aim-attachments-*.tar.gz' -mtime +7 -delete
```

`README.md` 在注销清理那条 crontab 旁边加：

```markdown
图片附件每天清理一次（没挂到记录超过 90 天、所挂记录删除超过 30 天、以及没有数据库记录的孤儿文件）：

    20 4 * * * docker exec -i aim-api-1 python scripts/purge_orphan_attachments.py >> /var/log/aim-attachments.log 2>&1

图片存放在数据卷 `aim_attachments`，每日备份脚本会一并打包。**`docker compose down -v` 同样会删掉这个卷。**
```

- [ ] **Step 6: 运行全量并提交**

```bash
cd services/api && PYTHONPATH=src python3 -m pytest tests/integration/records -q && cd ../.. && make -C services/api test
git add services/api infrastructure
git commit -m "feat(api): 图片附件的定期清理、注销清理与备份"
```

---

### Task 5：Eve 与模型

**Files:**
- Modify: `services/agent/Dockerfile`
- Modify: `services/agent/agent/channels/eve.ts`
- Modify: `services/agent/agent/lib/model-config.ts`
- Modify: `infrastructure/compose/compose.yaml`（`AIM_AGENT_MODEL` 默认值）
- Modify: `services/agent/agent/tools/create_record.ts`
- Modify: `services/agent/agent/instructions.md`
- Test: `services/agent/tests/model-config.test.ts`、`services/agent/tests/tools/authoring.test.ts`

**Interfaces:**
- Produces: 工具「新建记录」参数 `attachmentIds?: string[]`（UUID，最多 4 个）→ 请求体 `attachment_ids`

- [ ] **Step 1: 写失败测试**

`model-config.test.ts` 把两处 `deepseek-chat` 改成 `deepseek-flash`，并加一条：

```ts
test("the default model reads images", () => {
  const config = resolveAgentModelConfig({ EVE_USE_MOCK_MODEL: "0", DEEPSEEK_API_KEY: "k" });
  assert.equal(config.kind === "deepseek" && config.model, "deepseek-flash");
});
```

`authoring.test.ts` 追加：

```ts
test("create_record forwards the photo ids to attach", async () => {
  const id = "44444444-4444-4444-8444-444444444444";
  const { request } = await withStubbedApi({ record_id: "r3", attachment_count: 1 }, () =>
    createRecord.execute({ recordType: "note", content: "B 超单存档", attachmentIds: [id] }, scope),
  );
  const body = (await request?.clone().json()) as Record<string, unknown>;
  assert.deepEqual(body.attachment_ids, [id]);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd services/agent && npm test`
Expected: 2 条 FAIL

- [ ] **Step 3: 实现**

`model-config.ts`：默认值 `"deepseek-chat"` 改为 `"deepseek-flash"`。`compose.yaml` 的 `AIM_AGENT_MODEL: ${AIM_AGENT_MODEL:-deepseek-chat}` 改为 `deepseek-flash`。

`Dockerfile` 运行阶段在 `COPY --from=build /app/.output ./.output` 之后加：

```dockerfile
# Eve 暂存附件要用构建时准备好的沙箱模板；缺了它，发图片会让整段会话直接报错。
COPY --from=build /app/.eve/sandbox-cache ./.eve/sandbox-cache
```

`channels/eve.ts`：

```ts
export default eveChannel({
  // …原注释保留
  auth: [withAuthChallenges(aimSessionAuth, [{ scheme: "Bearer" }])],
  // 只收图片，单个不超过 2 MB（网页端已压缩到几百 KB）。超了返回 413/415。
  uploadPolicy: { allowedMediaTypes: ["image/*"], maxBytes: 2 * 1024 * 1024 },
});
```

`create_record.ts` 的 `inputSchema` 加：

```ts
    attachmentIds: z
      .array(z.string().uuid())
      .max(4)
      .optional()
      .describe("Ids of photos the user sent that should be kept with this record (from the image list in your context)."),
```

`execute` 请求体加 `attachment_ids: input.attachmentIds`。

`instructions.md` 在批量那段之后加：

```markdown
Images: the user may send photos. The ids of every photo sent in this conversation
are listed in your context as "images", in order ("message 2, photo 1").
- A checkup report: read the values you can see clearly and call `create_record`
  with recordType "checkup", the metrics you read, and the photo's id in
  `attachmentIds`. If a value is blurry or uncertain, do not guess — leave it out
  and tell the user which item you could not read.
- A question about something in a photo (food, a medicine box, a symptom):
  just answer. Do not create a record and do not attach the photo.
- "Keep/save this photo": create a `note` record describing it, with the photo
  attached.
- Never invent photo ids. If the user refers to a photo whose id is not in your
  context (for example in an older conversation), ask them to send it again.
```

- [ ] **Step 4: 构建、测试、镜像验证**

```bash
cd services/agent && npm run build && npm test && npm run lint
cd ../.. && docker compose --env-file .env --profile local -f infrastructure/compose/compose.yaml build eve \
  && docker compose --env-file .env --profile local -f infrastructure/compose/compose.yaml up -d --no-build eve
docker exec aim-eve-1 ls /app/.eve/sandbox-cache
```

Expected: 测试全过；容器里能列出沙箱模板目录。

- [ ] **Step 5: 提交**

```bash
git add services/agent infrastructure/compose/compose.yaml
git commit -m "feat(agent): 改用 deepseek-flash 读图，打包带上沙箱模板，新建记录可挂图片"
```

---

### Task 6：网页端压缩、上传与每轮图片上下文

**Files:**
- Create: `apps/agent-web/src/imageAttachments.ts`
- Create: `apps/agent-web/src/imageAttachments.test.ts`
- Modify: `apps/agent-web/src/entry.ts`、`apps/agent-web/src/entry.test.ts`
- Modify: `apps/agent-web/src/App.tsx`（运行时挂附件适配器、每轮上下文）

**Interfaces:**
- Produces:
  - `fitWithin(width, height, maxEdge) -> { width, height }`
  - `type SentImage = { id: string; message: number; index: number }`
  - `imagesContext(images: SentImage[]) -> string | null`（给模型看的图片清单文字）
  - `createImageAttachmentAdapter(options: { upload(blob: Blob): Promise<string>; onSent(id: string): void; count(): number; onError(message: string | null): void }) -> AttachmentAdapter`
  - `App.tsx` 里的 `attachmentError` 状态（字符串或空），Task 7 的输入框显示它
  - `withTurnContext(input, { page, images })`（取代 `withPageContext`）

- [ ] **Step 1: 写失败测试**

`imageAttachments.test.ts`：

```ts
import { expect, test } from "vitest";
import { fitWithin, imagesContext } from "./imageAttachments";

test("large photos shrink to fit 1600 on the long edge, small ones stay", () => {
  expect(fitWithin(4032, 3024, 1600)).toEqual({ width: 1600, height: 1200 });
  expect(fitWithin(3024, 4032, 1600)).toEqual({ width: 1200, height: 1600 });
  expect(fitWithin(800, 600, 1600)).toEqual({ width: 800, height: 600 });
});

test("the model sees every photo of the conversation in order", () => {
  expect(imagesContext([])).toBeNull();
  expect(
    imagesContext([
      { id: "a", message: 1, index: 1 },
      { id: "b", message: 3, index: 1 },
      { id: "c", message: 3, index: 2 },
    ]),
  ).toBe(
    "Photos the user sent in this conversation (use these ids in attachmentIds):\n" +
      "- message 1, photo 1: a\n- message 3, photo 1: b\n- message 3, photo 2: c",
  );
});
```

`entry.test.ts`：把 `withPageContext` 的用例改为 `withTurnContext`：

```ts
test("turn context carries the page and the photo list together", () => {
  const input = { message: "看看" };
  expect(withTurnContext(input, { page: null, images: null })).toBe(input);
  expect(withTurnContext(input, { page: { title: "番茄炒蛋", summary: "菜谱" }, images: "photos…" })).toEqual({
    message: "看看",
    clientContext: { page: { title: "番茄炒蛋", summary: "菜谱" }, images: "photos…" },
  });
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd apps/agent-web && npm test`
Expected: FAIL

- [ ] **Step 3: 实现**

`imageAttachments.ts`：

```ts
import type { AttachmentAdapter, CompleteAttachment, PendingAttachment } from "@assistant-ui/react";

export const MAX_IMAGES = 4;
const MAX_EDGE = 1600;
const QUALITY = 0.8;

export const fitWithin = (width: number, height: number, maxEdge: number) => {
  const scale = Math.min(1, maxEdge / Math.max(width, height));
  return { width: Math.round(width * scale), height: Math.round(height * scale) };
};

export type SentImage = { id: string; message: number; index: number };

/** 本段对话里发过的所有图片编号，按发送顺序。每轮都带给模型，它挂图时才有编号可用。 */
export const imagesContext = (images: readonly SentImage[]): string | null =>
  images.length
    ? "Photos the user sent in this conversation (use these ids in attachmentIds):\n" +
      images.map((image) => `- message ${image.message}, photo ${image.index}: ${image.id}`).join("\n")
    : null;

/** 压成最长边 1600 的 JPEG。iOS 的 HEIC 由 WebView 解码后同样走这里。 */
const compress = async (file: File): Promise<Blob> => {
  const bitmap = await createImageBitmap(file);
  const { width, height } = fitWithin(bitmap.width, bitmap.height, MAX_EDGE);
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, width, height);
  bitmap.close();
  return new Promise((resolve, reject) =>
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("图片处理失败"))), "image/jpeg", QUALITY),
  );
};

const toDataUrl = (blob: Blob): Promise<string> =>
  new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });

/**
 * 选图时压缩，发送时上传并转成消息内容。
 *
 * 上传失败时 send 抛错，这条消息就不会发出去——不能出现「模型看到了图、记录却挂不上」。
 * 出错的文案经 onError 交给页面显示（抛出的错误本身没人展示）；图片留在输入框里，再点发送即重试。
 */
export const createImageAttachmentAdapter = (options: {
  upload: (blob: Blob) => Promise<string>;
  onSent: (id: string) => void;
  count: () => number;
  onError: (message: string | null) => void;
}): AttachmentAdapter => ({
  accept: "image/*",
  async add({ file }): Promise<PendingAttachment> {
    if (options.count() >= MAX_IMAGES) {
      const message = `一次最多发 ${MAX_IMAGES} 张图片，多出的没有加上`;
      options.onError(message);
      throw new Error(message);
    }
    options.onError(null);
    const compressed = await compress(file);
    const name = file.name.replace(/\.[^.]+$/, "") + ".jpg";
    return {
      id: crypto.randomUUID(),
      type: "image",
      name,
      contentType: "image/jpeg",
      file: new File([compressed], name, { type: "image/jpeg" }),
      status: { type: "requires-action", reason: "composer-send" },
    };
  },
  async remove() {},
  async send(attachment): Promise<CompleteAttachment> {
    let id: string;
    try {
      id = await options.upload(attachment.file);
    } catch (cause) {
      options.onError("图片上传失败，请检查网络后再点发送");
      throw cause;
    }
    options.onError(null);
    options.onSent(id);
    return {
      ...attachment,
      id,
      status: { type: "complete" },
      content: [
        {
          type: "file",
          data: await toDataUrl(attachment.file),
          mimeType: "image/jpeg",
          filename: attachment.name,
        },
      ],
    };
  },
});
```

`entry.ts`：把 `withPageContext` 替换为：

```ts
/**
 * 每轮附带给模型的上下文：正在看的页面、本段对话发过的图片编号。
 * 用 Eve 的 clientContext：只进这一轮的模型调用、不写历史。
 */
export const withTurnContext = <T extends object>(
  input: T,
  context: { page: PageContext | null; images: string | null },
): T => {
  const clientContext: Record<string, unknown> = {};
  if (context.page) clientContext.page = context.page;
  if (context.images) clientContext.images = context.images;
  return Object.keys(clientContext).length ? { ...input, clientContext } : input;
};
```

`App.tsx` 的 `Conversation`：

```tsx
  // 本段对话发过的图片（发送顺序）。重开旧对话时为空——那时再说「存起来」，模型会请用户重发。
  const imagesRef = useRef<SentImage[]>([]);
  const [attachmentError, setAttachmentError] = useState<string | null>(null);
  const messageCountRef = useRef(0);
  const runtimeRef = useRef<ReturnType<typeof useEveAgentRuntime> | null>(null);
  const attachmentAdapter = useMemo(
    () =>
      createImageAttachmentAdapter({
        count: () => runtimeRef.current?.thread.composer.getState().attachments.length ?? 0,
        upload: async (blob) => {
          // 网页上下文里孕期编号是可选的（还没建孕期时没有），这时不能存图。
          if (!context.pregnancyId) throw new Error("还没有孕期信息，暂时不能发图片");
          const response = await fetch(
            `${context.eveOrigin ?? ""}/api/v1/pregnancies/${context.pregnancyId}/attachments`,
            {
              method: "POST",
              headers: { authorization: `Bearer ${context.token}`, "content-type": "image/jpeg" },
              body: blob,
            },
          );
          if (!response.ok) throw new Error("图片上传失败，请重试");
          return ((await response.json()) as { id: string }).id;
        },
        onSent: (id) => {
          const message = messageCountRef.current + 1;
          const index = imagesRef.current.filter((image) => image.message === message).length + 1;
          imagesRef.current = [...imagesRef.current, { id, message, index }];
        },
        onError: setAttachmentError,
      }),
    [context.eveOrigin, context.pregnancyId, context.token],
  );
```

`useEveAgentRuntime({...})` 加 `adapters: { attachments: attachmentAdapter }`，`prepareSend` 改为：

```tsx
    prepareSend: (input) => {
      messageCountRef.current += 1;
      return withTurnContext(input, { page: pageRef.current, images: imagesContext(imagesRef.current) });
    },
```

并在 `useEveAgentRuntime` 调用之后 `runtimeRef.current = runtime;`；把 `attachmentError` 传给 `Thread`（新增同名属性，Task 7 交给输入框显示）。import `useMemo`、`createImageAttachmentAdapter`、`imagesContext`、`type SentImage`、`withTurnContext`（去掉 `withPageContext`）。

- [ ] **Step 4: 测试、类型检查、构建**

Run: `cd apps/agent-web && npm test && npx tsc --noEmit && npm run build`
Expected: 通过。若 `adapters` 不在 `useEveAgentRuntime` 参数类型里，核对 `node_modules/@assistant-ui/eve/dist/useEveAgentRuntime.js` 中 `adapters?.attachments` 的读取位置，按实际参数名传入。

- [ ] **Step 5: 提交**

```bash
git add apps/agent-web
git commit -m "feat(web): 图片压缩、上传与每轮附带图片编号"
```

---

### Task 7：网页端选图、气泡缩略图与记录卡

**Files:**
- Create: `apps/agent-web/src/thread/Composer.tsx`
- Create: `apps/agent-web/src/thread/MessageImages.tsx`
- Modify: `apps/agent-web/src/App.tsx`（`Thread` 用新输入框、`UserMessage` 显示图片）
- Modify: `apps/agent-web/src/tools/CreateRecord.tsx`
- Modify: `apps/agent-web/src/styles.css`

**Interfaces:**
- Consumes: Task 6 的附件适配器（运行时已挂上）

- [ ] **Step 1: 输入框**

`thread/Composer.tsx`：

```tsx
import { AttachmentPrimitive, ComposerPrimitive, useAuiState } from "@assistant-ui/react";
import { useEffect, useState } from "react";

/** 输入框上方的待发缩略图：本地文件直接预览，可删。 */
const PendingImage = () => {
  const file = useAuiState((state) => state.attachment.file);
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    if (!file) return;
    const next = URL.createObjectURL(file);
    setUrl(next);
    return () => URL.revokeObjectURL(next);
  }, [file]);
  return (
    <AttachmentPrimitive.Root className="pending-image">
      {url ? <img src={url} alt="" /> : null}
      <AttachmentPrimitive.Remove className="pending-image__remove" aria-label="删掉这张图">
        ✕
      </AttachmentPrimitive.Remove>
    </AttachmentPrimitive.Root>
  );
};

export const Composer = ({ chip, error }: { chip?: React.ReactNode; error?: string | null }) => (
  <>
    {chip}
    {error ? (
      <p className="composer__error" role="alert">
        {error}
      </p>
    ) : null}
    <ComposerPrimitive.Root className="composer">
      <div className="composer__images">
        <ComposerPrimitive.Attachments components={{ Image: PendingImage, Attachment: PendingImage }} />
      </div>
      <div className="composer__row">
        <ComposerPrimitive.AddAttachment className="composer__image-button" aria-label="发图片" multiple>
          图片
        </ComposerPrimitive.AddAttachment>
        <ComposerPrimitive.Input className="composer__input" placeholder="告诉我你现在在担心什么" rows={1} />
        <ComposerPrimitive.Send className="composer__send">发送</ComposerPrimitive.Send>
      </div>
    </ComposerPrimitive.Root>
  </>
);
```

`App.tsx` 的 `Thread` 里把 `{chip}` 与原 `<ComposerPrimitive.Root>…</ComposerPrimitive.Root>` 整块替换为 `<Composer chip={chip} error={attachmentError} />`。

- [ ] **Step 2: 气泡里的图片**

`thread/MessageImages.tsx`：

```tsx
import { useAuiState } from "@assistant-ui/react";
import { useState } from "react";

/** 用户消息里的图片：历史里保存的是图片内容本身，可以直接显示。点开看大图。 */
export const MessageImage = () => {
  const src = useAuiState((state) => {
    for (const part of state.attachment.content ?? []) {
      if (part.type === "image") return part.image;
      if (part.type === "file" && part.mimeType.startsWith("image/")) return part.data;
    }
    return null;
  });
  const [open, setOpen] = useState(false);
  if (!src) return null;
  return (
    <>
      <button type="button" className="message-image" onClick={() => setOpen(true)}>
        <img src={src} alt="你发的图片" />
      </button>
      {open ? (
        <button type="button" className="image-viewer" onClick={() => setOpen(false)} aria-label="关闭大图">
          <img src={src} alt="" />
        </button>
      ) : null}
    </>
  );
};
```

`App.tsx` 的 `UserMessage`：

```tsx
const UserMessage = () => (
  <div className="msg msg--user">
    <div className="msg__images">
      <MessagePrimitive.Attachments components={{ Image: MessageImage, Attachment: MessageImage }} />
    </div>
    <MessagePrimitive.Parts />
  </div>
);
```

- [ ] **Step 3: 记录卡与样式**

`CreateRecord.tsx` 的 `Args` 加 `attachmentIds?: string[]`，在摘要文字之后加：

```tsx
        {args.attachmentIds?.length ? (
          <p className="tool-card__meta">已附上 {args.attachmentIds.length} 张图</p>
        ) : null}
```

`styles.css` 追加：

```css
.composer { flex-direction: column; align-items: stretch; }
.composer__row { display: flex; gap: 8px; align-items: flex-end; }
.composer__images { display: flex; gap: 8px; flex-wrap: wrap; }
.composer__images:empty { display: none; }
.composer__image-button { border: 1px solid var(--aim-separator); background: var(--aim-surface); color: var(--aim-accent); border-radius: 999px; padding: 8px 12px; font-size: 14px; }
.pending-image { position: relative; width: 64px; height: 64px; border-radius: 10px; overflow: hidden; }
.pending-image img { width: 100%; height: 100%; object-fit: cover; }
.pending-image__remove { position: absolute; top: 2px; right: 2px; border: none; border-radius: 999px; background: rgba(0,0,0,.55); color: #fff; width: 20px; height: 20px; font-size: 11px; }
.msg__images { display: flex; gap: 6px; flex-wrap: wrap; justify-content: flex-end; margin-bottom: 4px; }
.msg__images:empty { display: none; }
.message-image { border: none; padding: 0; background: none; }
.message-image img { width: 96px; height: 96px; object-fit: cover; border-radius: 12px; }
.image-viewer { position: fixed; inset: 0; z-index: 50; border: none; background: rgba(0,0,0,.9); display: flex; align-items: center; justify-content: center; }
.image-viewer img { max-width: 100%; max-height: 100%; }
.composer__error { margin: 0 0 6px; color: var(--aim-danger, #c0392b); font-size: 13px; }
```

`.composer` 原有的 `display` 若是行布局，以本段为准。

- [ ] **Step 4: 类型检查、构建与浏览器验证**

Run: `cd apps/agent-web && npx tsc --noEmit && npm test && npm run build`
Expected: 通过。若 `ComposerPrimitive.Attachments` 的 `components` 键名与本版本不同，以 `node_modules/@assistant-ui/react/dist` 中的类型为准。

本地栈 + `npm run dev`，用 `/tmp/aim-test-report.png`（Task 5 的测试报告图，可用 Pillow 重新生成）：
1. 点「图片」选这张图 → 输入框上方出现缩略图，✕ 可删；
2. 输入「帮我记下这张产检单」发送 → 气泡里有缩略图；AIM 建出产检记录卡，写着「已附上 1 张图」，五项数值正确；
3. 选 5 张图 → 只加上 4 张，输入框上方提示「一次最多发 4 张图片，多出的没有加上」；
4. 停掉本地业务服务再发送 → 提示「图片上传失败」，消息没有发出、图片仍在输入框；恢复服务后再点发送能发出去。若本版 assistant-ui 在发送失败时清空了输入框里的图片，改为在 `Conversation` 里先逐张调用上传、成功后再调用 `composer.send()`，保证失败时图片还在；
5. 刷新页面 → 历史里的图片仍能显示。

- [ ] **Step 5: 提交**

```bash
git add apps/agent-web
git commit -m "feat(web): 输入框可选图片，气泡与记录卡显示图片"
```

---

### Task 8：App 显示记录上的图片

**Files:**
- Modify: `apps/ios/AimApp/Resources/Info.plist`
- Modify: `apps/ios/AimApp/Features/Records/RecordDetailView.swift`
- Test: `apps/ios/AimApp/Tests/RecordStoreTests.swift`

**Interfaces:**
- Produces: `enum AttachmentRequest { static func make(id: String, environment: APIEnvironment) -> URLRequest? }`

- [ ] **Step 1: 写失败测试**

`RecordStoreTests.swift` 类内追加：

```swift
    func testAttachmentRequestCarriesTheLoginAndPointsAtTheImage() throws {
        let environment = APIEnvironment(
            baseURL: URL(string: "http://127.0.0.1:8100")!,
            eveBaseURL: URL(string: "http://127.0.0.1:2210")!,
            bearerToken: "aim.v1.token",
            accountID: nil, familyID: nil, pregnancyID: nil
        )
        let id = "44444444-4444-4444-8444-444444444444"
        let request = try XCTUnwrap(AttachmentRequest.make(id: id, environment: environment))
        XCTAssertEqual(request.url?.path, "/api/v1/attachments/\(id)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer aim.v1.token")
        XCTAssertNil(AttachmentRequest.make(id: "not-a-uuid", environment: environment))
    }
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath /tmp/aim-dd CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests test`
Expected: 编译失败（`AttachmentRequest` 未定义）

- [ ] **Step 3: 实现**

`Info.plist` 加：

```xml
	<key>NSCameraUsageDescription</key>
	<string>用于拍摄产检报告等，交给 AIM 识别。</string>
```

`RecordDetailView.swift` 文件末尾追加：

```swift
/// 取一张附件图片的请求。只接受合法编号，带上登录信息。
enum AttachmentRequest {
    static func make(id: String, environment: APIEnvironment) -> URLRequest? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return environment.businessRequest(path: "/api/v1/attachments/\(uuid.uuidString.lowercased())")
    }
}

/// 记录上挂的一张图片。加载失败显示占位，不影响页面其它内容。
private struct AttachmentThumbnail: View {
    let id: String
    let environment: APIEnvironment
    let onOpen: (UIImage) -> Void
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Button { onOpen(image) } label: {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                .buttonStyle(.plain)
            } else if failed {
                Image(systemName: "photo").foregroundStyle(Color.aimTextTertiary)
            } else {
                ProgressView()
            }
        }
        .frame(width: 96, height: 96)
        .background(Color.aimSurfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: id) {
            guard let request = AttachmentRequest.make(id: id, environment: environment),
                  let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let loaded = UIImage(data: data)
            else { failed = true; return }
            image = loaded
        }
    }
}

/// 全屏看大图，双指缩放，点一下关闭。
private struct AttachmentViewer: View {
    let image: UIImage
    let onClose: () -> Void
    @State private var scale: CGFloat = 1

    var body: some View {
        Color.black.ignoresSafeArea()
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) })
            }
            .onTapGesture(perform: onClose)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("关闭大图")
    }
}
```

`RecordDetailView` 里加状态 `@State private var viewingImage: UIImage?`；在 `contentSection` 之后插入：

```swift
            if !currentRecord.attachmentRefs.isEmpty {
                Section("图片") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AimMetrics.space8) {
                            ForEach(currentRecord.attachmentRefs, id: \.self) { id in
                                AttachmentThumbnail(id: id, environment: session.environment) { viewingImage = $0 }
                            }
                        }
                    }
                }
            }
```

`body` 末尾链上：

```swift
        .fullScreenCover(item: Binding(
            get: { viewingImage.map(IdentifiedImage.init) },
            set: { viewingImage = $0?.image }
        )) { item in
            AttachmentViewer(image: item.image) { viewingImage = nil }
        }
```

以及同文件内：

```swift
private struct IdentifiedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
```

（`Color.aimSurfaceSunken`、`AimMetrics.space8` 为既有设计令牌；若名字不同，以 `Core/DesignSystem/AimTheme.swift`、`AimMetrics.swift` 为准。）

- [ ] **Step 4: 运行确认通过**

Run: 同 Step 2
Expected: 全部通过

- [ ] **Step 5: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): 记录详情显示所挂图片，可全屏查看；声明相机权限用途"
```

---

### Task 9：端到端验证与上线准备

- [ ] **Step 1: 本地全链路**

重建本地 `api`、`eve`（`docker compose … build api eve && … up -d --no-build`），确认 `docker volume ls | grep aim_attachments`。在浏览器与模拟器里：
1. 发测试报告图说「帮我记下这张产检单」→ 产检记录五项正确、挂 1 张图；
2. 模拟器打开这条记录 → 「图片」区显示缩略图，点开全屏可缩放；
3. 发一张图问「这个孕期能吃吗」→ 只回答，不建记录；
4. 发一张图说「把这张存起来」→ 建备忘记录并挂图；
5. 刷新网页后说「把刚才那张也存起来」（旧对话、编号已不在上下文）→ AIM 请你重发，不编造编号；
6. `docker exec -i aim-api-1 python scripts/purge_orphan_attachments.py --dry-run` 能跑通。

- [ ] **Step 2: 全量自动化**

```bash
make -C services/api test lint
cd services/agent && npm run build && npm test && npm run lint && cd -
cd apps/agent-web && npm test && npx tsc --noEmit && npm run build && cd -
```

以及 iOS 单元测试（同 Task 8）。

- [ ] **Step 3: 上线清单（不在本计划内执行，部署前逐项确认）**

- 服务器 `.env` 加 `AIM_AGENT_MODEL=deepseek-flash`（或确认未设置、走默认值）；
- 部署后确认 `aim_attachments` 数据卷已创建、业务服务能写入；
- crontab 加附件清理任务；每日备份脚本更新到服务器 `/opt/aim/`；
- 迁移 `0010_attachments` 随业务服务启动自动执行；
- 真机实拍一张报告单走一遍。
