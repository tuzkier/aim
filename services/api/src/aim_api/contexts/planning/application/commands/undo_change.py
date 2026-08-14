from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from aim_api.contexts.planning.application.ports import PlanningUnitOfWork
from aim_api.contexts.planning.domain.errors import (
    PlanningAccessDenied,
    TaskChangeNotFound,
    TaskNotFound,
)
from aim_api.contexts.planning.domain.task import ActorType


@dataclass(frozen=True, slots=True)
class UndoChangeCommand:
    change_id: UUID
    account_id: UUID
    expected_version: int


async def execute(command: UndoChangeCommand, uow: PlanningUnitOfWork):
    change = await uow.repository.get_change(command.change_id)
    if change is None:
        raise TaskChangeNotFound("task change does not exist")
    task = await uow.repository.get_task(change.task_id)
    if task is None:
        raise TaskNotFound("task does not exist")
    pregnancy = await uow.pregnancy_ownership.get_pregnancy(task.pregnancy_id)
    if pregnancy is None or not await uow.family_membership.is_active_member(
        pregnancy.family_id, command.account_id
    ):
        raise PlanningAccessDenied("account cannot change this task")
    undo = task.undo_change(
        change,
        expected_version=command.expected_version,
        changed_by_actor_type=ActorType.account,
        changed_by_actor_id=command.account_id,
    )
    await uow.repository.save_task_change(task, undo, command.expected_version)
    await uow.commit()
    return task
