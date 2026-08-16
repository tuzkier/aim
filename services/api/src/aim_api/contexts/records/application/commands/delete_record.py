from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from aim_api.contexts.records.application.ports import RecordsUnitOfWork
from aim_api.contexts.records.domain.errors import RecordAccessDenied, RecordNotFound


@dataclass(frozen=True, slots=True)
class DeleteRecordCommand:
    record_id: UUID
    family_id: UUID
    account_id: UUID
    deleted_at: datetime | None = None


async def execute(command: DeleteRecordCommand, uow: RecordsUnitOfWork):
    if not await uow.family_membership.is_active_member(command.family_id, command.account_id):
        raise RecordAccessDenied("account cannot delete records for this family")
    record = await uow.repository.get_visible_record(
        command.record_id, command.family_id, command.account_id
    )
    if record is None:
        raise RecordNotFound("record does not exist or is not visible")
    record.soft_delete(command.account_id, now=command.deleted_at)
    await uow.repository.soft_delete(record, command.account_id)
    await uow.commit()
    return record
