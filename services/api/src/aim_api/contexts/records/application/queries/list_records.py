from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from aim_api.contexts.records.application.ports import RecordsUnitOfWork
from aim_api.contexts.records.domain.errors import RecordAccessDenied
from aim_api.contexts.records.domain.record import RecordType


@dataclass(frozen=True, slots=True)
class ListRecordsQuery:
    family_id: UUID
    account_id: UUID
    pregnancy_id: UUID | None = None
    record_type: RecordType | None = None
    occurred_from: datetime | None = None
    occurred_until: datetime | None = None


async def execute(query: ListRecordsQuery, uow: RecordsUnitOfWork):
    if not await uow.family_membership.is_active_member(query.family_id, query.account_id):
        raise RecordAccessDenied("account cannot read records for this family")
    return await uow.repository.list_visible_records(
        query.family_id,
        query.account_id,
        pregnancy_id=query.pregnancy_id,
        record_type=query.record_type,
        occurred_from=query.occurred_from,
        occurred_until=query.occurred_until,
    )
