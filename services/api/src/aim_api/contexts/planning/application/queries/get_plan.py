from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from aim_api.contexts.planning.application.ports import PlanningUnitOfWork
from aim_api.contexts.planning.domain.errors import PlanningAccessDenied, PlanNotFound


@dataclass(frozen=True, slots=True)
class GetPlanQuery:
    pregnancy_id: UUID
    account_id: UUID


async def can_read(uow: PlanningUnitOfWork, pregnancy_id: UUID, account_id: UUID) -> bool:
    """孕期存在且调用者是该家庭的活跃成员。

    单独拿出来，是因为读取入口要在读之前续上本周任务（会写库），
    而非家庭成员的请求不能触发任何写入——得先过这道校验再 sync。
    """
    pregnancy = await uow.pregnancy_ownership.get_pregnancy(pregnancy_id)
    return pregnancy is not None and await uow.family_membership.is_active_member(
        pregnancy.family_id, account_id
    )


async def execute(query: GetPlanQuery, uow: PlanningUnitOfWork):
    if not await can_read(uow, query.pregnancy_id, query.account_id):
        raise PlanningAccessDenied("account cannot read this plan")
    plan = await uow.repository.get_plan(query.pregnancy_id)
    if plan is None:
        raise PlanNotFound("pregnancy has no plan")
    return plan
