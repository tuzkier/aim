from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from aim_api.contexts.records.application.ports import RecordsUnitOfWork
from aim_api.contexts.records.domain.record import Record


@dataclass(frozen=True, slots=True)
class SaveRecordCommand:
    record: Record
    account_id: UUID


async def execute(command: SaveRecordCommand, uow: RecordsUnitOfWork) -> Record:
    command.record.assert_can_mutate(command.account_id)
    command.record.assert_attachment_refs_valid()
    await uow.repository.save_record(command.record, command.account_id)
    await uow.commit()
    return command.record
