from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from aim_api.contexts.records.application.ports import RecordsUnitOfWork
from aim_api.contexts.records.domain.errors import (
    RecordAccessDenied,
    RecordNotFound,
    RecordValidationError,
)
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility


@dataclass(frozen=True, slots=True)
class UpdateRecordCommand:
    record_id: UUID
    pregnancy_id: UUID
    family_id: UUID
    account_id: UUID
    changes: dict[str, Any]
    now: datetime | None = None


async def execute(command: UpdateRecordCommand, uow: RecordsUnitOfWork) -> Record:
    if not await uow.family_membership.is_active_member(command.family_id, command.account_id):
        raise RecordAccessDenied("account cannot update records for this family")
    record = await uow.repository.get_visible_record(
        command.record_id, command.family_id, command.account_id
    )
    if record is None or record.pregnancy_id != command.pregnancy_id:
        raise RecordNotFound("record does not exist or is not visible")
    record.assert_can_mutate(command.account_id)
    # 家人能改家庭记录的内容，但「谁能看」只有作者能定；带上与当前相同的值不算修改。
    if (
        "visibility" in command.changes
        and RecordVisibility(command.changes["visibility"]) is not record.visibility
        and record.author_account_id != command.account_id
    ):
        raise RecordAccessDenied("only the author can change who can see a record")

    if "occurred_at" in command.changes:
        record.occurred_at = command.changes["occurred_at"]
    if "visibility" in command.changes:
        record.visibility = RecordVisibility(command.changes["visibility"])
    Record.assert_visibility_allowed(record.record_type, record.visibility)
    if "title" in command.changes:
        record.title = command.changes["title"]
    if "content" in command.changes:
        record.content = command.changes["content"]
    if "structured_data" in command.changes:
        record.structured_data = command.changes["structured_data"]
    if not isinstance(record.structured_data, dict):
        raise RecordValidationError("structured_data must be a JSON object")
    Record._validate_payload(
        record.record_type, record.structured_data, record.content, record.title
    )
    record.structured_data = Record._with_defaults(record.record_type, record.structured_data)
    if record.record_type is RecordType.memory:
        record.title = record.structured_data["text"][:40]
    record.assert_attachment_refs_valid()
    record.updated_at = command.now or datetime.now(UTC)
    await uow.repository.save_record(record, command.account_id)
    await uow.commit()
    return record
