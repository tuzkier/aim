from __future__ import annotations

import hmac
from dataclasses import asdict
from datetime import UTC, datetime
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
    create_task,
    delay_task,
    delete_task,
    schedule_task,
    undo_change,
)
from aim_api.contexts.planning.application.commands.assign_task import AssignTaskCommand
from aim_api.contexts.planning.application.commands.complete_task import CompleteTaskCommand
from aim_api.contexts.planning.application.commands.create_task import CreateTaskCommand
from aim_api.contexts.planning.application.commands.delete_task import DeleteTaskCommand
from aim_api.contexts.planning.application.commands.delay_task import DelayTaskCommand
from aim_api.contexts.planning.application.commands.schedule_task import ScheduleTaskCommand
from aim_api.contexts.planning.application.commands.undo_change import UndoChangeCommand
from aim_api.contexts.planning.domain.task import ActorType
from aim_api.contexts.pregnancy.adapters.outbound.persistence.repositories import (
    SqlAlchemyPregnancyRepository,
)
from aim_api.contexts.pregnancy.application.commands import record_fact
from aim_api.contexts.pregnancy.application.commands.record_fact import RecordFactCommand
from aim_api.contexts.pregnancy.domain.fact import FactSource
from aim_api.contexts.records.adapters.outbound.persistence.repositories import (
    SqlAlchemyRecordsUnitOfWork,
)
from aim_api.contexts.records.application.commands import create_record, delete_record
from aim_api.contexts.records.application.commands.create_record import CreateRecordCommand
from aim_api.contexts.records.application.commands.delete_record import DeleteRecordCommand
from aim_api.contexts.records.application.queries import list_records
from aim_api.contexts.records.application.queries.list_records import ListRecordsQuery
from aim_api.contexts.records.domain.record import RecordType, RecordVisibility
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


class CreateTaskRequest(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    due_at: datetime | None = None


class DeleteTaskRequest(BaseModel):
    task_id: UUID


class CreateRecordRequest(BaseModel):
    record_type: RecordType
    structured_data: dict[str, Any] = Field(default_factory=dict)
    title: str | None = None
    content: str | None = None
    occurred_at: datetime | None = None


class DeleteRecordRequest(BaseModel):
    record_id: UUID


class GetGuidanceRequest(BaseModel):
    week: int = Field(ge=0)
    region: str = "CN-ZJ-HZ"


class UndoOperationRequest(BaseModel):
    change_id: UUID
    expected_version: int = Field(ge=1)
    approved: bool = False


class ListRecordsRequest(BaseModel):
    type: RecordType | None = None
    occurred_from: datetime | None = Field(default=None, alias="from")
    occurred_until: datetime | None = Field(default=None, alias="to")


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


# 时间线重设计 §6.1 的「直接执行」档：建普通待办、整理记录。
# 不打断对话，写入后由客户端 toast 提供撤销。
#
# 档位在服务端声明，而不是看调用方传来的 approved 标志——否则「执行前确认」
# 那一档等于形同虚设，任何调用方带上 approved: true 就能绕过。
DIRECT_EXECUTION_TOOLS = frozenset(
    {"create_task", "delete_task", "create_record", "delete_record"}
)


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

        if write and tool_name not in DIRECT_EXECUTION_TOOLS and not body.get("approved", False):
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


async def _list_records(session, context: AgentToolContext, body: dict[str, Any]):
    records = await list_records.execute(
        ListRecordsQuery(
            family_id=context.family_id,
            account_id=context.account_id,
            pregnancy_id=context.pregnancy_id,
            record_type=RecordType(body["type"]) if body.get("type") else None,
            occurred_from=body.get("occurred_from"),
            occurred_until=body.get("occurred_until"),
        ),
        SqlAlchemyRecordsUnitOfWork(session),
    )
    normalized = [
        {
            "id": str(record.id),
            "type": record.record_type.value,
            "occurred_at": record.occurred_at.isoformat(),
            "visibility": record.visibility.value,
            "title": record.title,
            "content": record.content,
            "structured_data": record.structured_data,
            "attachment_refs": record.attachment_refs,
        }
        for record in records
    ]
    return ({"records": normalized, "count": len(normalized)}, f"已读取 {len(normalized)} 条孕期记录")


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


async def _create_task(session, context: AgentToolContext, body: dict[str, Any]):
    """Agent 新建待办。actor 记为 agent，时间线据此显示「Agent 调整」。"""
    uow = SqlAlchemyPlanningUnitOfWork(session)
    task = await create_task.execute(
        CreateTaskCommand(
            pregnancy_id=context.pregnancy_id,
            account_id=context.account_id,
            title=body["title"],
            description=body.get("description"),
            due_at=_parse_datetime(body.get("due_at")),
            changed_by_actor_type=ActorType.agent,
        ),
        uow,
    )
    return ({"task_id": str(task.id), "title": task.title}, f"已添加待办：{task.title}")


async def _delete_task(session, context: AgentToolContext, body: dict[str, Any]):
    """撤销「Agent 新建待办」。任务不存在时也算成功——撤销可能被重放。"""
    uow = SqlAlchemyPlanningUnitOfWork(session)
    task_id = UUID(body["task_id"])
    existing = await uow.repository.get_task(task_id)
    if existing is not None and existing.pregnancy_id != context.pregnancy_id:
        raise ForbiddenError("task is outside the agent pregnancy scope")
    await delete_task.execute(
        DeleteTaskCommand(
            task_id=task_id,
            pregnancy_id=context.pregnancy_id,
            account_id=context.account_id,
        ),
        uow,
    )
    return ({"task_id": str(task_id)}, "已撤销新增的待办")


async def _create_record(session, context: AgentToolContext, body: dict[str, Any]):
    uow = SqlAlchemyRecordsUnitOfWork(session)
    record = await create_record.execute(
        CreateRecordCommand(
            pregnancy_id=context.pregnancy_id,
            family_id=context.family_id,
            account_id=context.account_id,
            record_type=RecordType(body["record_type"]),
            occurred_at=_parse_datetime(body.get("occurred_at")) or datetime.now(UTC),
            visibility=RecordVisibility.family,
            structured_data=body.get("structured_data") or {},
            title=body.get("title"),
            content=body.get("content"),
        ),
        uow,
    )
    return ({"record_id": str(record.id)}, "已记录")


async def _delete_record(session, context: AgentToolContext, body: dict[str, Any]):
    uow = SqlAlchemyRecordsUnitOfWork(session)
    await delete_record.execute(
        DeleteRecordCommand(
            record_id=UUID(body["record_id"]),
            family_id=context.family_id,
            account_id=context.account_id,
            pregnancy_id=context.pregnancy_id,
        ),
        uow,
    )
    return ({"record_id": body["record_id"]}, "已撤销记录")


def _parse_datetime(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))


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


@router.post("/list-records", response_model=ToolResult, include_in_schema=False)
async def list_records_endpoint(request: Request, payload: ListRecordsRequest):
    return await _run(request, "list_records", payload, _list_records)


@router.post("/update-task", response_model=ToolResult, include_in_schema=False)
async def update_task(request: Request, payload: UpdateTaskRequest):
    return await _run(request, "update_task", payload, _update_task, write=True)


@router.post("/create-task", response_model=ToolResult, include_in_schema=False)
async def create_task_endpoint(request: Request, payload: CreateTaskRequest):
    return await _run(request, "create_task", payload, _create_task, write=True)


@router.post("/delete-task", response_model=ToolResult, include_in_schema=False)
async def delete_task_endpoint(request: Request, payload: DeleteTaskRequest):
    return await _run(request, "delete_task", payload, _delete_task, write=True)


@router.post("/create-record", response_model=ToolResult, include_in_schema=False)
async def create_record_endpoint(request: Request, payload: CreateRecordRequest):
    return await _run(request, "create_record", payload, _create_record, write=True)


@router.post("/delete-record", response_model=ToolResult, include_in_schema=False)
async def delete_record_endpoint(request: Request, payload: DeleteRecordRequest):
    return await _run(request, "delete_record", payload, _delete_record, write=True)


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
