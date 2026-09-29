from __future__ import annotations

import hmac
from dataclasses import asdict
from datetime import UTC, datetime
from typing import Any, Literal
from uuid import UUID

from fastapi import APIRouter, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, model_validator
from starlette.exceptions import HTTPException

from aim_api.contexts.agent_access.adapters.outbound.persistence.repositories import (
    SqlAlchemyToolInvocationRepository,
)
from aim_api.contexts.agent_access.application.authorize_tool import (
    AgentToolContext,
    authorize_tool,
)
from aim_api.contexts.agent_access.adapters.inbound.http.operation_undo import undo_invocation
from aim_api.contexts.agent_access.application.execute_tool import effective_request_hash
from aim_api.contexts.agent_access.domain.tool_invocation import ToolInvocation
from aim_api.contexts.family.adapters.outbound.persistence.repositories import (
    SqlAlchemyFamilyRepository,
)
from aim_api.platform.auth.context import ensure_account_active, verify_session_token
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
    delete_task,
    assign_task,
    complete_task,
    create_task,
    delay_task,
    schedule_task,
)
from aim_api.contexts.planning.application.commands.assign_task import AssignTaskCommand
from aim_api.contexts.planning.application.commands.complete_task import CompleteTaskCommand
from aim_api.contexts.planning.application.commands.create_task import CreateTaskCommand
from aim_api.contexts.planning.application.commands.delay_task import DelayTaskCommand
from aim_api.contexts.planning.application.commands.delete_task import DeleteTaskCommand
from aim_api.contexts.planning.application.commands.schedule_task import ScheduleTaskCommand
from aim_api.contexts.planning.domain.errors import PlanningDomainError, TaskNotFound
from aim_api.contexts.planning.domain.task import ActorType
from aim_api.contexts.planning.domain.task_status import (
    InvalidTaskTransition,
    TaskVersionConflict,
)
from aim_api.contexts.pregnancy.adapters.outbound.persistence.repositories import (
    SqlAlchemyPregnancyRepository,
)
from aim_api.contexts.pregnancy.application.commands import record_fact
from aim_api.contexts.pregnancy.application.commands.record_fact import RecordFactCommand
from aim_api.contexts.pregnancy.domain.fact import FactSource
from aim_api.contexts.records.adapters.outbound.persistence.repositories import (
    SqlAlchemyRecordsUnitOfWork,
)
from aim_api.contexts.records.application.commands import create_record
from aim_api.contexts.records.application.commands.create_record import CreateRecordCommand
from aim_api.contexts.records.domain.errors import RecordValidationError
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


#: 一次批量操作的上限。再多就是模型在乱来，拆开做也更容易让用户核对。
MAX_BATCH = 50


def _exactly_one(batch, single, what: str) -> None:
    if (batch is None) == (single is None):
        raise ValueError(f"pass either a list of {what} or a single one, not both")


class TaskVersionRef(BaseModel):
    task_id: UUID
    expected_version: int = Field(ge=1)


class CompleteTaskToolRequest(BaseModel):
    #: 批量形式。单条的旧形式（task_id + expected_version 平铺）仍然接受。
    tasks: list[TaskVersionRef] | None = Field(default=None, min_length=1, max_length=MAX_BATCH)
    task_id: UUID | None = None
    expected_version: int | None = Field(default=None, ge=1)

    @model_validator(mode="after")
    def _one_form(self):
        _exactly_one(self.tasks, self.task_id, "tasks")
        if self.task_id is not None and self.expected_version is None:
            raise ValueError("expected_version is required with task_id")
        return self

    def refs(self) -> list[TaskVersionRef]:
        return self.tasks or [TaskVersionRef(task_id=self.task_id, expected_version=self.expected_version)]


class DeleteTaskToolRequest(BaseModel):
    task_ids: list[UUID] | None = Field(default=None, min_length=1, max_length=MAX_BATCH)
    task_id: UUID | None = None
    approved: bool = False

    @model_validator(mode="after")
    def _one_form(self):
        _exactly_one(self.task_ids, self.task_id, "task ids")
        return self


class RescheduleTaskRequest(BaseModel):
    task_id: UUID
    expected_version: int = Field(ge=1)
    #: schedule = 定下具体去做的时间（例如预约好的产检）；delay = 只把截止时间往后挪。
    kind: Literal["schedule", "delay"]
    at: datetime
    approved: bool = False


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


class TaskDraft(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    due_at: datetime | None = None


class CreateTaskRequest(BaseModel):
    #: 批量形式。单条的旧形式（title 等平铺）仍然接受。
    tasks: list[TaskDraft] | None = Field(default=None, min_length=1, max_length=MAX_BATCH)
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    due_at: datetime | None = None

    @model_validator(mode="after")
    def _one_form(self):
        _exactly_one(self.tasks, self.title, "tasks")
        return self


class CreateRecordRequest(BaseModel):
    record_type: RecordType
    structured_data: dict[str, Any] = Field(default_factory=dict)
    title: str | None = None
    content: str | None = None
    occurred_at: datetime | None = None


class CreateKnowledgeRequest(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    category: str
    form: str
    ingredients: list[str] | None = None
    steps: list[str] | None = None
    purposes: list[str] | None = None
    verdict: str | None = None
    reason: str | None = None
    body: str | None = None
    note: str | None = None
    # Eve 在用户确认后才带上它；档位判定见 _run。
    approved: bool = False


class GetGuidanceRequest(BaseModel):
    week: int = Field(ge=0)
    region: str = "CN-ZJ-HZ"


class UndoOperationRequest(BaseModel):
    operation_id: UUID


class ListRecordsRequest(BaseModel):
    type: RecordType | None = None
    occurred_from: datetime | None = Field(default=None, alias="from")
    occurred_until: datetime | None = Field(default=None, alias="to")


def _service_credential(request: Request) -> None:
    settings = request.app.state.settings
    service_authorization = request.headers.get("service-authorization", "")
    expected = f"Bearer {settings.agent_service_secret}"
    if not hmac.compare_digest(service_authorization, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid service credential"
        )


def _context(request: Request) -> AgentToolContext:
    _service_credential(request)
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
    {"create_task", "create_record", "complete_task", "undo_operation"}
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
            account_id=context.account_id,
            family_id=context.family_id,
            pregnancy_id=context.pregnancy_id,
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
        except RecordValidationError as error:
            # 模型把字段填错了。返回可读的冲突而不是 500——
            # 错误信息会回到模型手里，它才有机会改对重试。
            await session.rollback()
            raise ConflictError(str(error)) from error
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


#: 称呼为空时的回退，与 iOS 家庭页一致。
_ROLE_NAMES = {"mother": "妈妈", "father": "爸爸", "other_caregiver": "家人"}


async def _get_context(session, context: AgentToolContext, body: dict[str, Any]):
    pregnancy = await SqlAlchemyPregnancyRepository(session).get_pregnancy(context.pregnancy_id)
    plan = await SqlAlchemyPlanningUnitOfWork(session).repository.get_plan(context.pregnancy_id)
    family = await SqlAlchemyFamilyRepository(session).get_family(context.family_id)
    age = pregnancy.gestational_age() if pregnancy else None
    # member_id 就是账号 ID：assign_task 的 assigned_member_id 用的正是它。
    members = [
        {
            "member_id": str(member.account_id),
            "display_name": (member.nickname or "").strip()
            or _ROLE_NAMES.get(member.role.value, "家人"),
            "role": member.role.value,
        }
        for member in (family.members.values() if family else [])
        if member.status.value == "active"
    ]
    return (
        {
            "family_id": str(context.family_id),
            "pregnancy_id": str(context.pregnancy_id),
            "due_date": pregnancy.due_date.isoformat() if pregnancy else None,
            "gestational_age": {"weeks": age.weeks, "days": age.days} if age else None,
            "plan_id": str(plan.id) if plan else None,
            "self_member_id": str(context.account_id),
            "members": members,
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


async def _task_in_scope(uow, context: AgentToolContext, task_id: UUID):
    task = await uow.repository.get_task(task_id)
    if task is None or task.pregnancy_id != context.pregnancy_id:
        raise ForbiddenError("task is outside the agent pregnancy scope")
    return task


async def _task_write_result(uow, updated) -> dict[str, Any]:
    """写入结果统一带上 change_id：撤销靠它找回这次写入改了什么。"""
    change = await uow.repository.get_change_by_version(updated.id, updated.version)
    return {
        "task_id": str(updated.id),
        "title": updated.title,
        "version": updated.version,
        "status": updated.status.value,
        "change_id": str(change.id) if change else None,
    }


def _batch_result(done: list[dict[str, Any]], failed: list[dict[str, Any]]) -> dict[str, Any]:
    """批量结果。只有一项时顺带平铺它的字段，兼容单条调用方与旧的撤销记录。"""
    data: dict[str, Any] = {"tasks": done, "failed": failed}
    if len(done) == 1 and not failed:
        data.update(done[0])
    return data


def _failure_reason(error: Exception) -> str:
    if isinstance(error, TaskVersionConflict):
        return "这项待办刚被改过，请重新读取后再试"
    if isinstance(error, InvalidTaskTransition):
        return "这项待办已经是完成状态"
    if isinstance(error, (ForbiddenError, TaskNotFound)):
        return "找不到这项待办"
    return str(error)


async def _complete_task(session, context: AgentToolContext, body: dict[str, Any]):
    """完成一项或多项待办。逐项处理：某一项失败不拖累其它项，失败原因逐条返回。"""
    uow = SqlAlchemyPlanningUnitOfWork(session)
    refs = CompleteTaskToolRequest.model_validate(body).refs()
    done: list[dict[str, Any]] = []
    failed: list[dict[str, Any]] = []
    for ref in refs:
        try:
            task = await _task_in_scope(uow, context, ref.task_id)
            updated = await complete_task.execute(
                CompleteTaskCommand(
                    task_id=task.id,
                    account_id=context.account_id,
                    expected_version=ref.expected_version,
                ),
                uow,
            )
            done.append(await _task_write_result(uow, updated))
        except (ForbiddenError, PlanningDomainError, TaskVersionConflict, InvalidTaskTransition) as error:
            await session.rollback()
            failed.append({"task_id": str(ref.task_id), "reason": _failure_reason(error)})
    if not done:
        raise ConflictError("一项都没有完成：" + "；".join(f["reason"] for f in failed))
    titles = "、".join(t["title"] for t in done)
    summary = f"已完成待办：{titles}" + (f"（{len(failed)} 项没有完成）" if failed else "")
    return (_batch_result(done, failed), summary)


async def _delete_task(session, context: AgentToolContext, body: dict[str, Any]):
    """删掉不该存在的待办（加错了、重复了、不需要了），可一次多条。

    硬删除，不能撤销，所以在「执行前确认」档；一次确认覆盖整批。先核对整批都在
    本段孕期里再动手——有一条越界就一条都不删，免得删到一半才报错。
    没有它时，模型只能把加错的待办标成完成来「去掉」，留下假的完成记录。
    """
    uow = SqlAlchemyPlanningUnitOfWork(session)
    ids = [UUID(i) for i in (body.get("task_ids") or [body["task_id"]])]
    tasks = [await _task_in_scope(uow, context, task_id) for task_id in ids]
    for task in tasks:
        await delete_task.execute(
            DeleteTaskCommand(
                task_id=task.id,
                pregnancy_id=context.pregnancy_id,
                account_id=context.account_id,
            ),
            uow,
        )
    done = [{"task_id": str(task.id), "title": task.title} for task in tasks]
    return (_batch_result(done, []), "已删除待办：" + "、".join(t["title"] for t in done))


async def _reschedule_task(session, context: AgentToolContext, body: dict[str, Any]):
    uow = SqlAlchemyPlanningUnitOfWork(session)
    task = await _task_in_scope(uow, context, UUID(body["task_id"]))
    at = _parse_datetime(body["at"])
    if body["kind"] == "schedule":
        updated = await schedule_task.execute(
            ScheduleTaskCommand(
                task_id=task.id,
                account_id=context.account_id,
                expected_version=body["expected_version"],
                scheduled_for=at,
            ),
            uow,
        )
    else:
        updated = await delay_task.execute(
            DelayTaskCommand(
                task_id=task.id,
                account_id=context.account_id,
                expected_version=body["expected_version"],
                due_at=at,
            ),
            uow,
        )
    return (await _task_write_result(uow, updated), f"已改期：{updated.title}")


async def _create_task(session, context: AgentToolContext, body: dict[str, Any]):
    """Agent 新建一条或多条待办。actor 记为 agent，时间线据此显示「Agent 调整」。"""
    uow = SqlAlchemyPlanningUnitOfWork(session)
    drafts = body.get("tasks") or [
        {"title": body["title"], "description": body.get("description"), "due_at": body.get("due_at")}
    ]
    done: list[dict[str, Any]] = []
    for draft in drafts:
        task = await create_task.execute(
            CreateTaskCommand(
                pregnancy_id=context.pregnancy_id,
                account_id=context.account_id,
                title=draft["title"],
                description=draft.get("description"),
                due_at=_parse_datetime(draft.get("due_at")),
                changed_by_actor_type=ActorType.agent,
            ),
            uow,
        )
        done.append({"task_id": str(task.id), "title": task.title})
    summary = (
        f"已添加待办：{done[0]['title']}" if len(done) == 1 else f"已添加 {len(done)} 项待办"
    )
    return (_batch_result(done, []), summary)


async def _create_knowledge(session, context: AgentToolContext, body: dict[str, Any]):
    """写入一条知识条目。形态决定哪些字段必填，校验在领域层。"""
    uow = SqlAlchemyRecordsUnitOfWork(session)
    structured = {
        key: value
        for key, value in body.items()
        if key not in ("title", "approved") and value is not None
    }
    record = await create_record.execute(
        CreateRecordCommand(
            pregnancy_id=context.pregnancy_id,
            family_id=context.family_id,
            account_id=context.account_id,
            record_type=RecordType.knowledge,
            occurred_at=datetime.now(UTC),
            visibility=RecordVisibility.family,
            structured_data=structured,
            title=body["title"],
        ),
        uow,
    )
    return ({"record_id": str(record.id), "title": body["title"]}, f"已收录：{body['title']}")


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
    return (await _task_write_result(uow, updated), f"已更新任务负责人：{updated.title}")


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
    invocation = await SqlAlchemyToolInvocationRepository(session).get_by_operation(
        UUID(body["operation_id"])
    )
    if invocation is None or invocation.pregnancy_id != context.pregnancy_id:
        raise ConflictError("没有找到这次操作，可能不是在这段孕期里做的")
    return await undo_invocation(session, invocation, account_id=context.account_id)


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


@router.post("/complete-task", response_model=ToolResult, include_in_schema=False)
async def complete_task_endpoint(request: Request, payload: CompleteTaskToolRequest):
    return await _run(request, "complete_task", payload, _complete_task, write=True)


@router.post("/delete-task", response_model=ToolResult, include_in_schema=False)
async def delete_task_endpoint(request: Request, payload: DeleteTaskToolRequest):
    return await _run(request, "delete_task", payload, _delete_task, write=True)


@router.post("/reschedule-task", response_model=ToolResult, include_in_schema=False)
async def reschedule_task_endpoint(request: Request, payload: RescheduleTaskRequest):
    return await _run(request, "reschedule_task", payload, _reschedule_task, write=True)


@router.post("/create-task", response_model=ToolResult, include_in_schema=False)
async def create_task_endpoint(request: Request, payload: CreateTaskRequest):
    return await _run(request, "create_task", payload, _create_task, write=True)


@router.post("/create-knowledge", response_model=ToolResult, include_in_schema=False)
async def create_knowledge_endpoint(request: Request, payload: CreateKnowledgeRequest):
    return await _run(request, "create_knowledge", payload, _create_knowledge, write=True)


@router.post("/create-record", response_model=ToolResult, include_in_schema=False)
async def create_record_endpoint(request: Request, payload: CreateRecordRequest):
    return await _run(request, "create_record", payload, _create_record, write=True)


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


class ResolveSessionRequest(BaseModel):
    token: str


class ResolveSessionResponse(BaseModel):
    account_id: UUID
    family_id: UUID
    pregnancy_id: UUID | None


@router.post("/resolve-session", response_model=ResolveSessionResponse, include_in_schema=False)
async def resolve_session(request: Request, payload: ResolveSessionRequest):
    """把一张会话票换成可信的 account / family / pregnancy scope。

    Agent 运行时不持有 `AUTH_SECRET`，没法自己验签，所以身份必须来这里换。
    家庭与孕期一律由服务端按账号查出——**调用方自报的 scope 一概不作数**，
    否则运行时的身份就等于谁都能自选。改动这条前请先想清楚这一点。
    """
    _service_credential(request)

    settings = request.app.state.settings
    actor = verify_session_token(payload.token, settings.auth_secret)
    await ensure_account_active(request.app.state.database, actor.account_id)

    database = request.app.state.database
    async with database.session() as session:
        family = await SqlAlchemyFamilyRepository(session).get_first_family_for_account(
            actor.account_id
        )
        if family is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="account has no family"
            )
        pregnancy = await SqlAlchemyPregnancyRepository(session).get_first_pregnancy_for_family(
            family.id
        )

    return ResolveSessionResponse(
        account_id=actor.account_id,
        family_id=family.id,
        pregnancy_id=pregnancy.id if pregnancy is not None else None,
    )


class _Payload(BaseModel):
    payload: dict[str, Any]

    def model_dump(self, *args, **kwargs):
        return self.payload
