from __future__ import annotations

import hmac
from dataclasses import asdict
from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from fastapi import APIRouter, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from starlette.exceptions import HTTPException

from aim_api.contexts.agent_access.adapters.outbound.persistence.repositories import (
    SqlAlchemyToolInvocationRepository,
)
from aim_api.contexts.agent_access.application.authorize_tool import (
    AgentToolContext,
    authorize_tool,
)
from aim_api.contexts.agent_access.application.execute_tool import effective_request_hash
from aim_api.contexts.agent_access.domain.tool_invocation import ToolInvocation
from aim_api.contexts.family.adapters.outbound.persistence.repositories import (
    SqlAlchemyFamilyRepository,
)
from aim_api.contexts.guidance.application.queries.get_guidance import (
    GetGuidanceQuery,
)
from aim_api.contexts.guidance.application.queries.get_guidance import (
    execute as get_guidance,
)
from aim_api.contexts.planning.adapters.outbound.persistence.repositories import (
    SqlAlchemyPlanningUnitOfWork,
)
from aim_api.contexts.planning.application.commands import (
    assign_task,
    complete_task,
    delay_task,
    schedule_task,
    undo_change,
)
from aim_api.contexts.planning.application.commands.assign_task import AssignTaskCommand
from aim_api.contexts.planning.application.commands.complete_task import CompleteTaskCommand
from aim_api.contexts.planning.application.commands.delay_task import DelayTaskCommand
from aim_api.contexts.planning.application.commands.schedule_task import ScheduleTaskCommand
from aim_api.contexts.planning.application.commands.undo_change import UndoChangeCommand
from aim_api.contexts.pregnancy.adapters.outbound.persistence.repositories import (
    SqlAlchemyPregnancyRepository,
)
from aim_api.contexts.pregnancy.application.commands import record_fact
from aim_api.contexts.pregnancy.application.commands.record_fact import RecordFactCommand
from aim_api.contexts.pregnancy.domain.fact import FactSource
from aim_api.platform.http.errors import (
    ApprovalRequiredError,
    ConflictError,
    ForbiddenError,
    IdempotencyConflictError,
)

router = APIRouter(prefix="/internal/agent-tools", tags=["agent-tools"])


class ToolResult(BaseModel):
    operation_id: str
    status: Literal["completed", "approval_required"]
    summary: str
    data: dict[str, Any]


class UpdateTaskRequest(BaseModel):
    task_id: UUID
    action: Literal["schedule", "complete", "delay"]
    expected_version: int = Field(ge=1)
    scheduled_for: datetime | None = None
    due_at: datetime | None = None
    approved: bool = False
    family_id: UUID | None = None


class AssignTaskRequest(BaseModel):
    task_id: UUID
    assigned_member_id: UUID | None
    expected_version: int = Field(ge=1)
    approved: bool = False
    family_id: UUID | None = None


class RecordFactRequest(BaseModel):
    key: str = Field(min_length=1, max_length=120)
    value: Any
    source: FactSource
    approved: bool = False
    pregnancy_id: UUID | None = None


class GetGuidanceRequest(BaseModel):
    week: int = Field(ge=0)
    region: str = "CN-ZJ-HZ"


class UndoOperationRequest(BaseModel):
    change_id: UUID
    expected_version: int = Field(ge=1)
    approved: bool = False


def _context(request: Request) -> AgentToolContext:
    settings = request.app.state.settings
    service_authorization = request.headers.get("service-authorization", "")
    expected = f"Bearer {settings.agent_service_secret}"
    if not hmac.compare_digest(service_authorization, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid service credential"
        )
    try:
        return AgentToolContext(
            account_id=UUID(request.headers["actor-account-id"]),
            family_id=UUID(request.headers["family-id"]),
            pregnancy_id=UUID(request.headers["pregnancy-id"]),
            session_id=request.headers["eve-session-id"],
            call_id=request.headers["idempotency-key"],
        )
    except (KeyError, ValueError) as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="invalid agent scope"
        ) from error


async def _run(
    request: Request,
    tool_name: str,
    payload: BaseModel,
    handler,
    *,
    write: bool = False,
) -> JSONResponse:
    context = _context(request)
    body = payload.model_dump(mode="json")
    request_hash = effective_request_hash(tool_name, body)
    database = request.app.state.database
    async with database.session() as session:
        invocations = SqlAlchemyToolInvocationRepository(session)
        existing = await invocations.get(context.session_id, context.call_id)
        if existing is not None:
            if existing.request_hash != request_hash or existing.tool_name != tool_name:
                raise IdempotencyConflictError(
                    "idempotency key was already used by another request"
                )
            if existing.status.value == "approval_required":
                raise ApprovalRequiredError("approval is required before executing this write tool")
            return JSONResponse(content=existing.result)

        invocation = ToolInvocation.start(
            session_id=context.session_id,
            call_id=context.call_id,
            tool_name=tool_name,
            request_hash=request_hash,
        )
        family_membership = SqlAlchemyFamilyRepository(session)
        pregnancy_ownership = SqlAlchemyPregnancyRepository(session)
        try:
            await authorize_tool(context, family_membership, pregnancy_ownership)
        except PermissionError as error:
            await session.rollback()
            raise ForbiddenError(str(error)) from error

        if write and not body.get("approved", False):
            result = ToolResult(
                operation_id=str(invocation.operation_id),
                status="approval_required",
                summary="确认后才会修改家庭计划",
                data={},
            ).model_dump(mode="json")
            invocation.require_approval(result)
            await invocations.add(invocation)
            await invocations.commit()
            raise ApprovalRequiredError("approval is required before executing this write tool")

        try:
            data, summary = await handler(session, context, body)
        except PermissionError as error:
            await session.rollback()
            raise ForbiddenError(str(error)) from error
        except Exception:
            await session.rollback()
            raise

        result = ToolResult(
            operation_id=str(invocation.operation_id),
            status="completed",
            summary=summary,
            data=data,
        ).model_dump(mode="json")
        invocation.complete(result)
        await invocations.add(invocation)
        await invocations.commit()
        return JSONResponse(content=result)


async def _get_context(session, context: AgentToolContext, body: dict[str, Any]):
    pregnancy = await SqlAlchemyPregnancyRepository(session).get_pregnancy(context.pregnancy_id)
    plan = await SqlAlchemyPlanningUnitOfWork(session).repository.get_plan(context.pregnancy_id)
    age = pregnancy.gestational_age() if pregnancy else None
    return (
        {
            "family_id": str(context.family_id),
            "pregnancy_id": str(context.pregnancy_id),
            "due_date": pregnancy.due_date.isoformat() if pregnancy else None,
            "gestational_age": {"weeks": age.weeks, "days": age.days} if age else None,
            "plan_id": str(plan.id) if plan else None,
        },
        "已读取当前孕期上下文",
    )


async def _list_tasks(session, context: AgentToolContext, body: dict[str, Any]):
    plan = await SqlAlchemyPlanningUnitOfWork(session).repository.get_plan(context.pregnancy_id)
    tasks = (
        []
        if plan is None
        else [
            {
                "task_id": str(task.id),
                "title": task.title,
                "status": task.status.value,
                "version": task.version,
                "due_at": task.due_at.isoformat() if task.due_at else None,
                "assigned_member_id": str(task.assigned_member_id)
                if task.assigned_member_id
                else None,
            }
            for task in plan.tasks
        ]
    )
    return ({"tasks": tasks}, f"已读取 {len(tasks)} 项家庭任务")


async def _update_task(session, context: AgentToolContext, body: dict[str, Any]):
    uow = SqlAlchemyPlanningUnitOfWork(session)
    task_id = UUID(body["task_id"])
    task = await uow.repository.get_task(task_id)
    if task is None or task.pregnancy_id != context.pregnancy_id:
        raise ForbiddenError("task is outside the agent pregnancy scope")
    action = body["action"]
    if action == "schedule":
        if body.get("scheduled_for") is None:
            raise ConflictError("scheduled_for is required")
        updated = await schedule_task.execute(
            ScheduleTaskCommand(
                task_id=task_id,
                account_id=context.account_id,
                expected_version=body["expected_version"],
                scheduled_for=datetime.fromisoformat(body["scheduled_for"].replace("Z", "+00:00")),
            ),
            uow,
        )
    elif action == "complete":
        updated = await complete_task.execute(
            CompleteTaskCommand(
                task_id=task_id,
                account_id=context.account_id,
                expected_version=body["expected_version"],
            ),
            uow,
        )
    else:
        if body.get("due_at") is None:
            raise ConflictError("due_at is required")
        updated = await delay_task.execute(
            DelayTaskCommand(
                task_id=task_id,
                account_id=context.account_id,
                expected_version=body["expected_version"],
                due_at=datetime.fromisoformat(body["due_at"].replace("Z", "+00:00")),
            ),
            uow,
        )
    return (
        {"task_id": str(updated.id), "version": updated.version, "status": updated.status.value},
        f"已更新任务：{updated.title}",
    )


async def _assign_task(session, context: AgentToolContext, body: dict[str, Any]):
    uow = SqlAlchemyPlanningUnitOfWork(session)
    task = await uow.repository.get_task(UUID(body["task_id"]))
    if task is None or task.pregnancy_id != context.pregnancy_id:
        raise ForbiddenError("task is outside the agent pregnancy scope")
    updated = await assign_task.execute(
        AssignTaskCommand(
            task_id=task.id,
            account_id=context.account_id,
            assigned_member_id=(
                UUID(body["assigned_member_id"]) if body.get("assigned_member_id") else None
            ),
            expected_version=body["expected_version"],
        ),
        uow,
    )
    return (
        {"task_id": str(updated.id), "version": updated.version},
        f"已更新任务负责人：{updated.title}",
    )


async def _record_fact(session, context: AgentToolContext, body: dict[str, Any]):
    # The command uses the Pregnancy repository through the same unit-of-work boundary.
    from aim_api.contexts.pregnancy.adapters.outbound.persistence.repositories import (
        SqlAlchemyPregnancyUnitOfWork,
    )

    pregnancy_uow = SqlAlchemyPregnancyUnitOfWork(session)
    result = await record_fact.execute(
        RecordFactCommand(
            pregnancy_id=context.pregnancy_id,
            account_id=context.account_id,
            key=body["key"],
            value=body.get("value"),
            source=FactSource(body["source"]),
        ),
        pregnancy_uow,
    )
    return (
        {"fact_id": str(result.fact.id), "status": result.fact.status.value},
        f"已记录孕期事实：{result.fact.key}",
    )


async def _guidance(session, context: AgentToolContext, body: dict[str, Any]):
    items = get_guidance(
        GetGuidanceQuery(
            gestational_week=int(body["week"]), region=str(body.get("region", "CN-ZJ-HZ"))
        )
    )
    return ({"items": [asdict(item) for item in items]}, f"已读取 {len(items)} 条指导内容")


async def _undo_operation(session, context: AgentToolContext, body: dict[str, Any]):
    uow = SqlAlchemyPlanningUnitOfWork(session)
    change = await uow.repository.get_change(UUID(body["change_id"]))
    if change is None:
        raise ConflictError("task change does not exist")
    task = await uow.repository.get_task(change.task_id)
    if task is None or task.pregnancy_id != context.pregnancy_id:
        raise ForbiddenError("change is outside the agent pregnancy scope")
    updated = await undo_change.execute(
        UndoChangeCommand(
            change_id=change.id,
            account_id=context.account_id,
            expected_version=body["expected_version"],
        ),
        uow,
    )
    return (
        {"task_id": str(updated.id), "version": updated.version},
        f"已撤销任务变更：{updated.title}",
    )


@router.post("/get-pregnancy-context", response_model=ToolResult, include_in_schema=False)
async def get_pregnancy_context(request: Request, payload: dict[str, Any] | None = None):
    return await _run(
        request, "get_pregnancy_context", _Payload(payload=payload or {}), _get_context
    )


@router.post("/list-tasks", response_model=ToolResult, include_in_schema=False)
async def list_tasks(request: Request, payload: dict[str, Any] | None = None):
    return await _run(request, "list_tasks", _Payload(payload=payload or {}), _list_tasks)


@router.post("/update-task", response_model=ToolResult, include_in_schema=False)
async def update_task(request: Request, payload: UpdateTaskRequest):
    return await _run(request, "update_task", payload, _update_task, write=True)


@router.post("/assign-task", response_model=ToolResult, include_in_schema=False)
async def assign_task_endpoint(request: Request, payload: AssignTaskRequest):
    return await _run(request, "assign_task", payload, _assign_task, write=True)


@router.post("/record-pregnancy-fact", response_model=ToolResult, include_in_schema=False)
async def record_pregnancy_fact(request: Request, payload: RecordFactRequest):
    return await _run(request, "record_pregnancy_fact", payload, _record_fact, write=True)


@router.post("/get-guidance", response_model=ToolResult, include_in_schema=False)
async def get_guidance_endpoint(request: Request, payload: GetGuidanceRequest):
    return await _run(request, "get_guidance", payload, _guidance)


@router.post("/undo-operation", response_model=ToolResult, include_in_schema=False)
async def undo_operation(request: Request, payload: UndoOperationRequest):
    return await _run(request, "undo_operation", payload, _undo_operation, write=True)


class _Payload(BaseModel):
    payload: dict[str, Any]

    def model_dump(self, *args, **kwargs):
        return self.payload
