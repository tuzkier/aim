"""按操作编号撤销 AIM 做过的一次写入。

模型和卡片上的「撤销」按钮都走这里：每个写工具的结果里本来就有 operation_id，
服务端也逐条存了调用记录，所以撤销不需要模型记住任何别的 ID。
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Request
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from aim_api.contexts.agent_access.adapters.outbound.persistence.repositories import (
    SqlAlchemyToolInvocationRepository,
)
from aim_api.contexts.agent_access.domain.tool_invocation import (
    ToolInvocation,
    ToolInvocationStatus,
)
from aim_api.contexts.planning.adapters.outbound.persistence.repositories import (
    SqlAlchemyPlanningUnitOfWork,
)
from aim_api.contexts.planning.application.commands import delete_task, undo_change
from aim_api.contexts.planning.application.commands.delete_task import DeleteTaskCommand
from aim_api.contexts.planning.application.commands.undo_change import UndoChangeCommand
from aim_api.contexts.planning.domain.task_status import (
    InvalidTaskTransition,
    TaskVersionConflict,
)
from aim_api.contexts.records.adapters.outbound.persistence.repositories import (
    SqlAlchemyRecordsUnitOfWork,
)
from aim_api.contexts.records.application.commands import delete_record
from aim_api.contexts.records.application.commands.delete_record import DeleteRecordCommand
from aim_api.contexts.records.domain.errors import RecordNotFound
from aim_api.platform.auth.context import authenticate_active
from aim_api.platform.http.errors import ConflictError, ForbiddenError, NotFoundError

#: 撤销「新建」即删除；撤销对待办的修改即还原那条 task change。
_DELETE_TASK = {"create_task"}
_DELETE_RECORD = {"create_record", "create_knowledge"}
_REVERT_CHANGE = {"complete_task", "reschedule_task", "assign_task"}


async def undo_invocation(
    session: AsyncSession, invocation: ToolInvocation, *, account_id: UUID
) -> tuple[dict[str, Any], str]:
    if invocation.account_id is None or invocation.account_id != account_id:
        raise ForbiddenError("这次操作不属于当前账号")
    if invocation.status is not ToolInvocationStatus.completed:
        raise ConflictError("这次操作没有执行，不需要撤销")

    base = {"operation_id": str(invocation.operation_id)}
    if invocation.undone_at is not None:
        return ({**base, "already_undone": True}, "这次操作已经撤销过了")

    tool = invocation.tool_name
    data = invocation.result.get("data", {})
    if tool == "record_pregnancy_fact":
        raise ConflictError("孕期信息不能撤销，直接告诉我正确的值即可")
    if tool == "delete_task":
        raise ConflictError("删除的待办不能撤销，需要的话重新建一条")

    if tool in _DELETE_TASK:
        # 批量新建的结果在 data.tasks 里；单条的旧记录只有 data.task_id。
        task_ids = [t["task_id"] for t in data.get("tasks") or []] or [data["task_id"]]
        for task_id in task_ids:
            await delete_task.execute(
                DeleteTaskCommand(
                    task_id=UUID(task_id),
                    pregnancy_id=invocation.pregnancy_id,
                    account_id=account_id,
                ),
                SqlAlchemyPlanningUnitOfWork(session),
            )
        summary = "已撤销新建的待办" if len(task_ids) == 1 else f"已撤销新建的 {len(task_ids)} 项待办"
    elif tool in _DELETE_RECORD:
        try:
            await delete_record.execute(
                DeleteRecordCommand(
                    record_id=UUID(data["record_id"]),
                    family_id=invocation.family_id,
                    account_id=account_id,
                    pregnancy_id=invocation.pregnancy_id,
                ),
                SqlAlchemyRecordsUnitOfWork(session),
            )
        except RecordNotFound:
            # 用户已经在别处删掉了：撤销想要的结果已经达成。
            await session.rollback()
        summary = "已撤销新建的记录"
    elif tool in _REVERT_CHANGE:
        change_ids = [t.get("change_id") for t in data.get("tasks") or []] or [data.get("change_id")]
        if not all(change_ids):
            raise ConflictError("这次操作缺少变更记录，不能撤销")
        reverted: list[str] = []
        conflicted = 0
        for change_id in change_ids:
            uow = SqlAlchemyPlanningUnitOfWork(session)
            change = await uow.repository.get_change(UUID(change_id))
            if change is None:
                conflicted += 1
                continue
            try:
                updated = await undo_change.execute(
                    UndoChangeCommand(
                        change_id=change.id,
                        account_id=account_id,
                        expected_version=change.version_after,
                    ),
                    uow,
                )
                reverted.append(updated.title)
            except (TaskVersionConflict, InvalidTaskTransition):
                await session.rollback()
                conflicted += 1
        if not reverted:
            raise ConflictError("这项待办之后又被改过，不能直接撤销")
        summary = "已撤销：" + "、".join(reverted)
        if conflicted:
            summary += f"（{conflicted} 项之后又被改过，没有撤销）"
    else:
        raise ConflictError("这类操作不能撤销")

    invocations = SqlAlchemyToolInvocationRepository(session)
    await invocations.mark_undone(invocation.operation_id, datetime.now(UTC))
    await session.commit()
    return ({**base, "already_undone": False}, summary)


router = APIRouter(tags=["agent-operations"])


class UndoOperationResponse(BaseModel):
    operation_id: UUID
    summary: str
    already_undone: bool


@router.post(
    "/api/v1/agent/operations/{operation_id}/undo", response_model=UndoOperationResponse
)
async def undo_operation_from_card(operation_id: UUID, request: Request) -> UndoOperationResponse:
    """对话卡片上的「撤销」。与模型调用的 undo_operation 共用同一套反向逻辑。"""
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        invocation = await SqlAlchemyToolInvocationRepository(session).get_by_operation(
            operation_id
        )
        if invocation is None:
            raise NotFoundError("没有找到这次操作")
        data, summary = await undo_invocation(session, invocation, account_id=actor.account_id)
    return UndoOperationResponse(
        operation_id=operation_id, summary=summary, already_undone=data["already_undone"]
    )
