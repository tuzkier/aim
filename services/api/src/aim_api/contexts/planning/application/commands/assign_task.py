from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from aim_api.contexts.planning.application.ports import PlanningUnitOfWork
from aim_api.contexts.planning.domain.errors import PlanningAccessDenied, TaskNotFound
from aim_api.contexts.planning.domain.task import ActorType
from aim_api.contexts.planning.domain.task_status import TaskAssignmentError


@dataclass(frozen=True, slots=True)
class AssignTaskCommand:
    task_id: UUID
    account_id: UUID
    assigned_member_id: UUID | None
    expected_version: int


async def execute(command: AssignTaskCommand, uow: PlanningUnitOfWork):
    task = await uow.repository.get_task(command.task_id)
    if task is None:
        raise TaskNotFound("task does not exist")
    pregnancy = await uow.pregnancy_ownership.get_pregnancy(task.pregnancy_id)
    if pregnancy is None or not await uow.family_membership.is_active_member(
        pregnancy.family_id, command.account_id
    ):
        raise PlanningAccessDenied("account cannot change this task")
    if command.assigned_member_id is not None and not await uow.family_membership.is_active_member(
        pregnancy.family_id, command.assigned_member_id
    ):
        raise TaskAssignmentError("assignee is not an active family member")
    change = task.assign(
        command.assigned_member_id,
        expected_version=command.expected_version,
        changed_by_actor_type=ActorType.account,
        changed_by_actor_id=command.account_id,
    )
    await uow.repository.save_task_change(task, change, command.expected_version)
    await uow.commit()
    return task
