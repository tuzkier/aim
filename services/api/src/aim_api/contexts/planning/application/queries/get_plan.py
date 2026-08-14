from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from aim_api.contexts.planning.application.ports import PlanningUnitOfWork
from aim_api.contexts.planning.domain.errors import PlanningAccessDenied, PlanNotFound


@dataclass(frozen=True, slots=True)
class GetPlanQuery:
    pregnancy_id: UUID
    account_id: UUID


async def execute(query: GetPlanQuery, uow: PlanningUnitOfWork):
    pregnancy = await uow.pregnancy_ownership.get_pregnancy(query.pregnancy_id)
    if pregnancy is None or not await uow.family_membership.is_active_member(
        pregnancy.family_id, query.account_id
    ):
        raise PlanningAccessDenied("account cannot read this plan")
    plan = await uow.repository.get_plan(query.pregnancy_id)
    if plan is None:
        raise PlanNotFound("pregnancy has no plan")
    return plan
