from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from aim_api.contexts.records.application.ports import RecordsUnitOfWork
from aim_api.contexts.records.domain.errors import RecordAccessDenied, RecordNotFound


@dataclass(frozen=True, slots=True)
class GetRecordQuery:
    record_id: UUID
    family_id: UUID
    account_id: UUID
    pregnancy_id: UUID | None = None


async def execute(query: GetRecordQuery, uow: RecordsUnitOfWork):
    if not await uow.family_membership.is_active_member(query.family_id, query.account_id):
        raise RecordAccessDenied("account cannot read records for this family")
    record = await uow.repository.get_visible_record(
        query.record_id, query.family_id, query.account_id
    )
    if record is None or (
        query.pregnancy_id is not None and record.pregnancy_id != query.pregnancy_id
    ):
        raise RecordNotFound("record does not exist or is not visible")
    return record
