from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from aim_api.contexts.planning.application.ports import PlanningUnitOfWork
from aim_api.contexts.planning.domain.errors import PlanningAccessDenied, TaskNotFound
from aim_api.contexts.planning.domain.task import ActorType


@dataclass(frozen=True, slots=True)
class DelayTaskCommand:
    task_id: UUID
    account_id: UUID
    expected_version: int
    due_at: datetime


async def execute(command: DelayTaskCommand, uow: PlanningUnitOfWork):
    task = await uow.repository.get_task(command.task_id)
    if task is None:
        raise TaskNotFound("task does not exist")
    pregnancy = await uow.pregnancy_ownership.get_pregnancy(task.pregnancy_id)
    if pregnancy is None or not await uow.family_membership.is_active_member(
        pregnancy.family_id, command.account_id
    ):
        raise PlanningAccessDenied("account cannot change this task")
    change = task.delay(
        command.due_at,
        expected_version=command.expected_version,
        changed_by_actor_type=ActorType.account,
        changed_by_actor_id=command.account_id,
    )
    await uow.repository.save_task_change(task, change, command.expected_version)
    await uow.commit()
    return task
