from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from uuid import UUID, uuid4

from aim_api.contexts.pregnancy.application.ports import PregnancyUnitOfWork
from aim_api.contexts.pregnancy.domain.errors import PregnancyAccessDenied
from aim_api.contexts.pregnancy.domain.pregnancy import Pregnancy


@dataclass(frozen=True, slots=True)
class CreatePregnancyCommand:
    family_id: UUID
    account_id: UUID
    due_date: date
    now: datetime | None = None


async def execute(command: CreatePregnancyCommand, uow: PregnancyUnitOfWork) -> Pregnancy:
    if not await uow.family_membership.is_active_member(command.family_id, command.account_id):
        raise PregnancyAccessDenied("account is not an active member of this family")
    pregnancy = Pregnancy.create(
        uuid4(),
        command.family_id,
        command.due_date,
        command.account_id,
        now=command.now,
    )
    await uow.repository.add_pregnancy(pregnancy)
    await uow.commit()
    return pregnancy
