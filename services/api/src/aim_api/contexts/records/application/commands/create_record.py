from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any
from uuid import UUID, uuid4

from aim_api.contexts.records.application.ports import RecordsUnitOfWork
from aim_api.contexts.records.domain.attachment import MAX_ATTACHMENTS_PER_RECORD
from aim_api.contexts.records.domain.errors import (
    RecordAccessDenied,
    RecordNotFound,
    RecordValidationError,
)
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility


@dataclass(frozen=True, slots=True)
class CreateRecordCommand:
    pregnancy_id: UUID
    family_id: UUID
    account_id: UUID
    record_type: RecordType
    occurred_at: datetime
    visibility: RecordVisibility
    structured_data: dict[str, Any]
    title: str | None = None
    content: str | None = None
    now: datetime | None = None
    #: 要挂到这条记录上的图片编号。必须属于同一家庭、尚未挂到别的记录。
    attachment_ids: tuple[UUID, ...] = ()


async def execute(command: CreateRecordCommand, uow: RecordsUnitOfWork) -> Record:
    record = await stage(command, uow)
    await uow.commit()
    return record


async def stage(command: CreateRecordCommand, uow: RecordsUnitOfWork) -> Record:
    """校验并写入一条记录，但不提交。

    要和别的记录同进同退时用它（例如产检报告与随它攒下的问题），
    由调用方在整批写完后自己 commit；中途出错由调用方 rollback。
    """
    pregnancy = await uow.pregnancy_ownership.get_pregnancy(command.pregnancy_id)
    if pregnancy is None:
        raise RecordNotFound("pregnancy does not exist")
    if pregnancy.family_id != command.family_id:
        raise RecordAccessDenied("pregnancy does not belong to this family")
    if not await uow.family_membership.is_active_member(command.family_id, command.account_id):
        raise RecordAccessDenied("account cannot create records for this family")
    await _check_attachments(command, uow)
    record = Record.create(
        record_id=uuid4(),
        pregnancy_id=command.pregnancy_id,
        family_id=command.family_id,
        author_account_id=command.account_id,
        record_type=command.record_type,
        occurred_at=command.occurred_at,
        visibility=command.visibility,
        title=command.title,
        content=command.content,
        structured_data=command.structured_data,
        attachment_refs=[str(attachment_id) for attachment_id in command.attachment_ids],
        now=command.now,
    )
    if command.record_type is RecordType.memory:
        await uow.repository.reserve_memory_slot(command.family_id)
    await uow.repository.add_record(record)
    if command.attachment_ids:
        await uow.attachments.attach(list(command.attachment_ids), record.id)
    return record


async def _check_attachments(command: CreateRecordCommand, uow: RecordsUnitOfWork) -> None:
    if len(command.attachment_ids) > MAX_ATTACHMENTS_PER_RECORD:
        raise RecordValidationError("一条记录最多挂 4 张图片")
    if len(set(command.attachment_ids)) != len(command.attachment_ids):
        raise RecordValidationError("同一张图片不能重复挂")
    for attachment_id in command.attachment_ids:
        attachment = await uow.attachments.get(attachment_id)
        # 别的家庭的图片与不存在的图片同一说法：不暴露编号是否存在。
        if attachment is None or attachment.family_id != command.family_id:
            raise RecordValidationError("找不到这张图片，请让用户重新发一次")
        if attachment.record_id is not None:
            raise RecordValidationError("这张图片已经挂在别的记录上了")
