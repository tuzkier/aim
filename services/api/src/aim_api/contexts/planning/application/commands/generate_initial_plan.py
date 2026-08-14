from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID, uuid4

from aim_api.contexts.planning.application.ports import PlanningUnitOfWork
from aim_api.contexts.planning.domain.errors import PlanningAccessDenied
from aim_api.contexts.planning.domain.plan import PregnancyPlan
from aim_api.contexts.planning.domain.task import ActorType, Task, TaskSourceType
from aim_api.contexts.planning.domain.task_status import TaskAssignmentError


@dataclass(frozen=True, slots=True)
class TaskSeed:
    title: str
    source_type: TaskSourceType
    source_id: str | None
    changed_by_actor_type: ActorType
    changed_by_actor_id: UUID | None
    description: str | None = None
    due_at: datetime | None = None
    assigned_member_id: UUID | None = None


@dataclass(frozen=True, slots=True)
class GenerateInitialPlanCommand:
    pregnancy_id: UUID
    family_id: UUID
    account_id: UUID
    tasks: tuple[TaskSeed, ...] = ()
    now: datetime | None = None


async def execute(command: GenerateInitialPlanCommand, uow: PlanningUnitOfWork) -> PregnancyPlan:
    pregnancy = await uow.pregnancy_ownership.get_pregnancy(command.pregnancy_id)
    if pregnancy is None or pregnancy.family_id != command.family_id:
        raise PlanningAccessDenied("pregnancy does not belong to this family")
    if not await uow.family_membership.is_active_member(command.family_id, command.account_id):
        raise PlanningAccessDenied("account is not an active family member")
    if await uow.repository.get_plan(command.pregnancy_id) is not None:
        raise ValueError("pregnancy already has a plan")

    plan = PregnancyPlan.create(uuid4(), command.pregnancy_id, now=command.now)
    await uow.repository.add_plan(plan)
    for seed in command.tasks:
        if seed.assigned_member_id is not None and not await uow.family_membership.is_active_member(
            command.family_id, seed.assigned_member_id
        ):
            raise TaskAssignmentError("assignee is not an active family member")
        task = Task.create(
            task_id=uuid4(),
            plan_id=plan.id,
            pregnancy_id=command.pregnancy_id,
            title=seed.title,
            description=seed.description,
            source_type=seed.source_type,
            source_id=seed.source_id,
            changed_by_actor_type=seed.changed_by_actor_type,
            changed_by_actor_id=seed.changed_by_actor_id,
            due_at=seed.due_at,
            assigned_member_id=seed.assigned_member_id,
            now=command.now,
        )
        plan.add_task(task)
        await uow.repository.add_task(task)
    await uow.commit()
    return plan
