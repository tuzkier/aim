from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any
from uuid import UUID, uuid4

from aim_api.contexts.records.application.ports import RecordsUnitOfWork
from aim_api.contexts.records.domain.errors import RecordAccessDenied, RecordNotFound
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


async def execute(command: CreateRecordCommand, uow: RecordsUnitOfWork) -> Record:
    pregnancy = await uow.pregnancy_ownership.get_pregnancy(command.pregnancy_id)
    if pregnancy is None:
        raise RecordNotFound("pregnancy does not exist")
    if pregnancy.family_id != command.family_id:
        raise RecordAccessDenied("pregnancy does not belong to this family")
    if not await uow.family_membership.is_active_member(command.family_id, command.account_id):
        raise RecordAccessDenied("account cannot create records for this family")
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
        attachment_refs=[],
        now=command.now,
    )
    await uow.repository.add_record(record)
    await uow.commit()
    return record
