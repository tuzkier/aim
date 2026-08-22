from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID, uuid4

from aim_api.contexts.planning.application.ports import PlanningUnitOfWork
from aim_api.contexts.planning.domain.errors import PlanningAccessDenied, PlanNotFound
from aim_api.contexts.planning.domain.task import ActorType, Task, TaskSourceType
from aim_api.contexts.planning.domain.task_status import TaskAssignmentError


@dataclass(frozen=True, slots=True)
class CreateTaskCommand:
    pregnancy_id: UUID
    account_id: UUID
    title: str
    description: str | None = None
    due_at: datetime | None = None
    source_type: TaskSourceType = TaskSourceType.user
    source_id: str | None = None
    assigned_member_id: UUID | None = None
    # Agent 建的任务要标成 agent 来源，时间线才会显示「Agent 调整」。
    # 默认仍是 account，公开 API 的行为不变。
    changed_by_actor_type: ActorType = ActorType.account


async def execute(command: CreateTaskCommand, uow: PlanningUnitOfWork) -> Task:
    pregnancy = await uow.pregnancy_ownership.get_pregnancy(command.pregnancy_id)
    if pregnancy is None or not await uow.family_membership.is_active_member(
        pregnancy.family_id, command.account_id
    ):
        raise PlanningAccessDenied("account cannot create tasks for this pregnancy")

    plan = await uow.repository.get_plan(command.pregnancy_id)
    if plan is None:
        raise PlanNotFound("pregnancy does not have a plan")

    if command.assigned_member_id is not None and not await uow.family_membership.is_active_member(
        pregnancy.family_id, command.assigned_member_id
    ):
        raise TaskAssignmentError("assignee is not an active family member")

    task = Task.create(
        task_id=uuid4(),
        plan_id=plan.id,
        pregnancy_id=command.pregnancy_id,
        title=command.title,
        description=command.description,
        source_type=command.source_type,
        source_id=command.source_id,
        changed_by_actor_type=command.changed_by_actor_type,
        changed_by_actor_id=command.account_id,
        due_at=command.due_at,
        assigned_member_id=command.assigned_member_id,
    )
    await uow.repository.add_task(task)
    await uow.commit()
    return task
