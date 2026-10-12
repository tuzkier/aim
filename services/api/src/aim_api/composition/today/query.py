from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from uuid import UUID

from aim_api.contexts.planning.application.ports import PlanningUnitOfWork
from aim_api.contexts.planning.domain.errors import PlanningAccessDenied, PlanNotFound
from aim_api.contexts.planning.domain.task import Task


@dataclass(frozen=True, slots=True)
class FamilyTaskCount:
    assigned_member_id: UUID | None
    open_count: int


@dataclass(frozen=True, slots=True)
class TodayReadModel:
    pregnancy_id: UUID
    as_of: date
    gestational_age: object
    priority_task: Task | None
    upcoming_tasks: tuple[Task, ...]
    agent_status: dict[str, object]
    family_task_counts: tuple[FamilyTaskCount, ...]


@dataclass(frozen=True, slots=True)
class GetTodayQuery:
    pregnancy_id: UUID
    account_id: UUID
    as_of: date


async def execute(query: GetTodayQuery, uow: PlanningUnitOfWork) -> TodayReadModel:
    pregnancy = await uow.pregnancy_ownership.get_pregnancy(query.pregnancy_id)
    if pregnancy is None or not await uow.family_membership.is_active_member(
        pregnancy.family_id, query.account_id
    ):
        raise PlanningAccessDenied("account cannot read this Today view")
    plan = await uow.repository.get_plan(query.pregnancy_id)
    if plan is None:
        raise PlanNotFound("pregnancy has no plan")

    open_tasks = [task for task in plan.tasks if task.status.value == "todo"]
    open_tasks.sort(key=lambda task: (task.due_at is None, task.due_at, task.id.hex))
    priority = open_tasks[0] if open_tasks else None
    upcoming = [
        task
        for task in sorted(
            (task for task in plan.tasks if task.status.value not in ("done", "cancelled")),
            key=lambda task: (task.due_at is None, task.due_at, task.id.hex),
        )
        if priority is None or task.id != priority.id
    ][:3]

    counts: dict[UUID | None, int] = {}
    for task in plan.tasks:
        if task.status.value not in ("done", "cancelled"):
            counts[task.assigned_member_id] = counts.get(task.assigned_member_id, 0) + 1

    return TodayReadModel(
        pregnancy_id=query.pregnancy_id,
        as_of=query.as_of,
        gestational_age=pregnancy.gestational_age(query.as_of),
        priority_task=priority,
        upcoming_tasks=tuple(upcoming),
        agent_status={"state": "idle", "last_run_at": None},
        family_task_counts=tuple(
            FamilyTaskCount(assigned_member_id=member_id, open_count=count)
            for member_id, count in counts.items()
        ),
    )
