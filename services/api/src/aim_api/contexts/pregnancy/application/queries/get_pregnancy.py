from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from aim_api.contexts.pregnancy.application.ports import PregnancyUnitOfWork
from aim_api.contexts.pregnancy.domain.errors import PregnancyAccessDenied, PregnancyNotFound


@dataclass(frozen=True, slots=True)
class GetPregnancyQuery:
    pregnancy_id: UUID
    account_id: UUID


async def execute(query: GetPregnancyQuery, uow: PregnancyUnitOfWork):
    pregnancy = await uow.repository.get_pregnancy(query.pregnancy_id)
    if pregnancy is None:
        raise PregnancyNotFound("pregnancy does not exist")
    if not await uow.family_membership.is_active_member(pregnancy.family_id, query.account_id):
        raise PregnancyAccessDenied("account cannot read this pregnancy")
    return pregnancy
