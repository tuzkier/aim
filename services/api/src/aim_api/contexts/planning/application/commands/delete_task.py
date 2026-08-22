from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from aim_api.contexts.planning.application.ports import PlanningUnitOfWork
from aim_api.contexts.planning.domain.errors import PlanningAccessDenied


@dataclass(frozen=True, slots=True)
class DeleteTaskCommand:
    task_id: UUID
    pregnancy_id: UUID
    account_id: UUID


async def execute(command: DeleteTaskCommand, uow: PlanningUnitOfWork) -> None:
    """删除任务。

    这是「撤销 Agent 新建的待办」所走的路径：`undo_change` 做的是字段级还原，
    把任务还原成变更前的快照，而新建没有前值可还原。

    删除是硬删除，任务的 `task_changes` 会随之消失。找不到任务时静默返回——
    撤销可能被重放（toast 连点、网络重试），重复删除不应报错。
    """
    pregnancy = await uow.pregnancy_ownership.get_pregnancy(command.pregnancy_id)
    if pregnancy is None or not await uow.family_membership.is_active_member(
        pregnancy.family_id, command.account_id
    ):
        raise PlanningAccessDenied("account cannot delete tasks for this pregnancy")

    task = await uow.repository.get_task(command.task_id)
    if task is None:
        return
    if task.pregnancy_id != command.pregnancy_id:
        raise PlanningAccessDenied("task belongs to another pregnancy")

    await uow.repository.delete_task(task.id)
    await uow.commit()
