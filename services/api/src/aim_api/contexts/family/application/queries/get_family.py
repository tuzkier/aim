from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from aim_api.contexts.family.application.ports import FamilyUnitOfWork


@dataclass(frozen=True, slots=True)
class GetFamilyQuery:
    family_id: UUID
    account_id: UUID


async def execute(query: GetFamilyQuery, uow: FamilyUnitOfWork):
    family = await uow.repository.get_family(query.family_id)
    if family is None:
        raise ValueError("family does not exist")
    family.active_member(query.account_id)
    return family
