from __future__ import annotations

from datetime import date
from uuid import UUID

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel

from aim_api.composition.today.query import GetTodayQuery, TodayReadModel, execute
from aim_api.contexts.planning.adapters.inbound.http.router import TaskResponse, _task_response
from aim_api.contexts.planning.adapters.outbound.persistence.repositories import (
    SqlAlchemyPlanningUnitOfWork,
)
from aim_api.contexts.planning.domain.errors import PlanningAccessDenied, PlanNotFound
from aim_api.platform.auth.context import authenticate_active
from aim_api.platform.http.errors import ForbiddenError, NotFoundError

router = APIRouter(tags=["today"])


class GestationalAgeTodayResponse(BaseModel):
    weeks: int
    days: int


class FamilyTaskCountResponse(BaseModel):
    assigned_member_id: UUID | None
    open_count: int


class TodayResponse(BaseModel):
    pregnancy_id: UUID
    as_of: date
    gestational_age: GestationalAgeTodayResponse
    priority_task: TaskResponse | None
    upcoming_tasks: list[TaskResponse]
    agent_status: dict[str, object]
    family_task_counts: list[FamilyTaskCountResponse]


def _response(model: TodayReadModel) -> TodayResponse:
    return TodayResponse(
        pregnancy_id=model.pregnancy_id,
        as_of=model.as_of,
        gestational_age=GestationalAgeTodayResponse(
            weeks=model.gestational_age.weeks, days=model.gestational_age.days
        ),
        priority_task=_task_response(model.priority_task) if model.priority_task else None,
        upcoming_tasks=[_task_response(task) for task in model.upcoming_tasks],
        agent_status=model.agent_status,
        family_task_counts=[
            FamilyTaskCountResponse(
                assigned_member_id=count.assigned_member_id, open_count=count.open_count
            )
            for count in model.family_task_counts
        ],
    )


@router.get("/api/v1/pregnancies/{pregnancy_id}/today", response_model=TodayResponse)
async def get_today_endpoint(
    pregnancy_id: UUID, request: Request, as_of: date | None = Query(default=None)
) -> TodayResponse:
    actor = await authenticate_active(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyPlanningUnitOfWork(session)
        try:
            model = await execute(
                GetTodayQuery(
                    pregnancy_id=pregnancy_id,
                    account_id=actor.account_id,
                    as_of=as_of or date.today(),
                ),
                uow,
            )
        except PlanningAccessDenied as error:
            await uow.rollback()
            raise ForbiddenError(str(error)) from error
        except PlanNotFound as error:
            await uow.rollback()
            raise NotFoundError(str(error)) from error
        return _response(model)
