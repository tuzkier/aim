from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID

from fastapi import APIRouter, Request, Response
from pydantic import BaseModel, Field, field_validator, model_validator

from aim_api.contexts.guidance.application.queries.get_guidance import initial_plan_items
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
from aim_api.contexts.planning.application.commands.delay_task import DelayTaskCommand
from aim_api.contexts.planning.application.commands.delete_task import DeleteTaskCommand
from aim_api.contexts.planning.application.commands.generate_initial_plan import (
    GenerateInitialPlanCommand,
    TaskSeed,
)
from aim_api.contexts.planning.application.commands.schedule_task import ScheduleTaskCommand
from aim_api.contexts.planning.application.commands.undo_change import UndoChangeCommand
from aim_api.contexts.planning.application.queries import get_plan
from aim_api.contexts.planning.application.queries.get_plan import GetPlanQuery
from aim_api.contexts.planning.domain.errors import (
    PlanningAccessDenied,
    PlanningDomainError,
    PlanNotFound,
    TaskChangeNotFound,
    TaskNotFound,
)
from aim_api.contexts.planning.domain.task import ActorType, Task, TaskSourceType
from aim_api.contexts.planning.domain.task_status import (
    InvalidTaskTransition,
    TaskAssignmentError,
    TaskVersionConflict,
)
from aim_api.contexts.records.adapters.outbound.persistence.repositories import (
    SqlAlchemyRecordsUnitOfWork,
)
from aim_api.contexts.records.application.queries import get_record
from aim_api.contexts.records.application.queries.get_record import GetRecordQuery
from aim_api.contexts.records.domain.errors import RecordAccessDenied, RecordNotFound
from aim_api.platform.auth.context import ActorContext, authenticate
from aim_api.platform.http.errors import (
    ConflictError,
    ForbiddenError,
    NotFoundError,
    VersionConflictError,
)

router = APIRouter(tags=["planning"])


class TaskResponse(BaseModel):
    id: UUID
    plan_id: UUID
    pregnancy_id: UUID
    title: str
    description: str | None
    status: str
    source_type: str
    source_id: str | None
    changed_by_actor_type: str
    changed_by_actor_id: UUID | None
    version: int
    scheduled_for: datetime | None
    due_at: datetime | None
    assigned_member_id: UUID | None
    created_at: datetime
    updated_at: datetime


class PlanResponse(BaseModel):
    id: UUID
    pregnancy_id: UUID
    version: int
    created_at: datetime
    updated_at: datetime
    tasks: list[TaskResponse]


class ExpectedVersionRequest(BaseModel):
    expected_version: int = Field(ge=1)


class ScheduleTaskRequest(ExpectedVersionRequest):
    scheduled_for: datetime


class DelayTaskRequest(ExpectedVersionRequest):
    due_at: datetime


class AssignTaskRequest(ExpectedVersionRequest):
    assigned_member_id: UUID | None


class GeneratePlanRequest(BaseModel):
    as_of: date | None = None


class CreateTaskRequest(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    due_at: datetime | None = None
    assigned_member_id: UUID | None = None
    record_id: UUID | None = None
    source_type: TaskSourceType = TaskSourceType.user
    source_id: str | None = Field(default=None, max_length=200)

    @field_validator("title")
    @classmethod
    def title_must_not_be_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("title cannot be blank")
        return value

    @model_validator(mode="after")
    def validate_source(self) -> CreateTaskRequest:
        if self.record_id is not None:
            if self.source_type not in (TaskSourceType.user, TaskSourceType.record):
                raise ValueError("record_id can only be used with record source")
            if self.source_id is not None and self.source_id != str(self.record_id):
                raise ValueError("source_id must match record_id")
            return self
        if self.source_type is not TaskSourceType.user:
            raise ValueError("only user or validated record task sources can be created")
        return self


def _task_response(task: Task) -> TaskResponse:
    return TaskResponse(
        id=task.id,
        plan_id=task.plan_id,
        pregnancy_id=task.pregnancy_id,
        title=task.title,
        description=task.description,
        status=task.status.value,
        source_type=task.source_type.value,
        source_id=task.source_id,
        changed_by_actor_type=task.changed_by_actor_type.value,
        changed_by_actor_id=task.changed_by_actor_id,
        version=task.version,
        scheduled_for=task.scheduled_for,
        due_at=task.due_at,
        assigned_member_id=task.assigned_member_id,
        created_at=task.created_at,
        updated_at=task.updated_at,
    )


def _plan_response(plan) -> PlanResponse:
    return PlanResponse(
        id=plan.id,
        pregnancy_id=plan.pregnancy_id,
        version=plan.version,
        created_at=plan.created_at,
        updated_at=plan.updated_at,
        tasks=[_task_response(task) for task in plan.tasks],
    )


def _translate(error: Exception) -> None:
    if isinstance(error, PlanningAccessDenied):
        raise ForbiddenError(str(error)) from error
    if isinstance(error, (PlanNotFound, TaskNotFound, TaskChangeNotFound)):
        raise NotFoundError(str(error)) from error
    if isinstance(error, TaskVersionConflict):
        raise VersionConflictError(str(error)) from error
    if isinstance(error, (InvalidTaskTransition, TaskAssignmentError)):
        raise ConflictError(str(error)) from error
    if isinstance(error, PlanningDomainError):
        raise ConflictError(str(error)) from error
    raise error


def _actor(request: Request) -> ActorContext:
    return authenticate(request)


@router.get("/api/v1/pregnancies/{pregnancy_id}/plan", response_model=PlanResponse)
async def get_plan_endpoint(pregnancy_id: UUID, request: Request) -> PlanResponse:
    actor = _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyPlanningUnitOfWork(session)
        try:
            plan = await get_plan.execute(
                GetPlanQuery(pregnancy_id=pregnancy_id, account_id=actor.account_id), uow
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return _plan_response(plan)


@router.post(
    "/api/v1/pregnancies/{pregnancy_id}/plan",
    response_model=PlanResponse,
    status_code=201,
)
async def generate_plan_endpoint(
    pregnancy_id: UUID, payload: GeneratePlanRequest, request: Request
) -> PlanResponse:
    actor = _actor(request)
    as_of = payload.as_of or date.today()
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyPlanningUnitOfWork(session)
        try:
            pregnancy = await uow.pregnancy_ownership.get_pregnancy(pregnancy_id)
            if pregnancy is None:
                raise PlanNotFound("pregnancy does not exist")
            age = pregnancy.gestational_age(as_of)
            seeds = tuple(
                TaskSeed(
                    title=item.title,
                    description=item.summary,
                    source_type=TaskSourceType.template,
                    source_id=item.id,
                    changed_by_actor_type=ActorType.system,
                    changed_by_actor_id=None,
                    due_at=datetime.combine(
                        as_of + timedelta(days=item.due_in_days), time(9, 0), tzinfo=UTC
                    ),
                )
                for item in initial_plan_items(age.weeks)
            )
            from aim_api.contexts.planning.application.commands import generate_initial_plan

            plan = await generate_initial_plan.execute(
                GenerateInitialPlanCommand(
                    pregnancy_id=pregnancy_id,
                    family_id=pregnancy.family_id,
                    account_id=actor.account_id,
                    tasks=seeds,
                    now=datetime.combine(as_of, time(0), tzinfo=UTC),
                ),
                uow,
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return _plan_response(plan)


async def _run_task_command(request: Request, command_fn, command):
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyPlanningUnitOfWork(session)
        try:
            task = await command_fn(command, uow)
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return _task_response(task)


async def _validated_record_source(
    request: Request, pregnancy_id: UUID, record_id: UUID, actor: ActorContext
) -> str:
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyRecordsUnitOfWork(session)
        try:
            pregnancy = await uow.pregnancy_ownership.get_pregnancy(pregnancy_id)
            if pregnancy is None:
                raise PlanNotFound("pregnancy does not exist")
            await get_record.execute(
                GetRecordQuery(
                    record_id=record_id,
                    family_id=pregnancy.family_id,
                    account_id=actor.account_id,
                    pregnancy_id=pregnancy_id,
                ),
                uow,
            )
        except RecordAccessDenied as error:
            await uow.rollback()
            raise PlanningAccessDenied("account cannot use this record") from error
        except RecordNotFound as error:
            await uow.rollback()
            raise TaskNotFound("record does not exist or is not visible") from error
        except Exception:
            await uow.rollback()
            raise
    return str(record_id)


@router.post(
    "/api/v1/pregnancies/{pregnancy_id}/tasks",
    response_model=TaskResponse,
    status_code=201,
)
async def create_task_endpoint(
    pregnancy_id: UUID, payload: CreateTaskRequest, request: Request
) -> TaskResponse:
    actor = _actor(request)
    source_type = payload.source_type
    source_id = payload.source_id
    try:
        if payload.record_id is not None:
            source_type = TaskSourceType.record
            source_id = await _validated_record_source(
                request, pregnancy_id, payload.record_id, actor
            )
        return await _run_task_command(
            request,
            create_task.execute,
            CreateTaskCommand(
                pregnancy_id=pregnancy_id,
                account_id=actor.account_id,
                title=payload.title,
                description=payload.description,
                due_at=payload.due_at,
                source_type=source_type,
                source_id=source_id,
                assigned_member_id=payload.assigned_member_id,
            ),
        )
    except Exception as error:
        _translate(error)


@router.delete("/api/v1/pregnancies/{pregnancy_id}/tasks/{task_id}", status_code=204)
async def delete_task_endpoint(pregnancy_id: UUID, task_id: UUID, request: Request) -> Response:
    """硬删除任务。

    这是「撤销 Agent 新建的待办」的落地路径：undo_change 做的是字段级还原，
    新建没有可还原的前值。删除会级联清除该任务的 task_changes。

    任务不存在时同样返回 204——撤销可能被重放，重复删除不该报错。
    """
    actor = _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyPlanningUnitOfWork(session)
        try:
            await delete_task.execute(
                DeleteTaskCommand(
                    task_id=task_id,
                    pregnancy_id=pregnancy_id,
                    account_id=actor.account_id,
                ),
                uow,
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
    return Response(status_code=204)


@router.post("/api/v1/tasks/{task_id}/schedule", response_model=TaskResponse)
async def schedule_task_endpoint(
    task_id: UUID, payload: ScheduleTaskRequest, request: Request
) -> TaskResponse:
    actor = _actor(request)
    return await _run_task_command(
        request,
        schedule_task.execute,
        ScheduleTaskCommand(
            task_id=task_id,
            account_id=actor.account_id,
            expected_version=payload.expected_version,
            scheduled_for=payload.scheduled_for,
        ),
    )


@router.post("/api/v1/tasks/{task_id}/complete", response_model=TaskResponse)
async def complete_task_endpoint(
    task_id: UUID, payload: ExpectedVersionRequest, request: Request
) -> TaskResponse:
    actor = _actor(request)
    return await _run_task_command(
        request,
        complete_task.execute,
        CompleteTaskCommand(
            task_id=task_id,
            account_id=actor.account_id,
            expected_version=payload.expected_version,
        ),
    )


@router.post("/api/v1/tasks/{task_id}/delay", response_model=TaskResponse)
async def delay_task_endpoint(
    task_id: UUID, payload: DelayTaskRequest, request: Request
) -> TaskResponse:
    actor = _actor(request)
    return await _run_task_command(
        request,
        delay_task.execute,
        DelayTaskCommand(
            task_id=task_id,
            account_id=actor.account_id,
            expected_version=payload.expected_version,
            due_at=payload.due_at,
        ),
    )


@router.post("/api/v1/tasks/{task_id}/assign", response_model=TaskResponse)
async def assign_task_endpoint(
    task_id: UUID, payload: AssignTaskRequest, request: Request
) -> TaskResponse:
    actor = _actor(request)
    return await _run_task_command(
        request,
        assign_task.execute,
        AssignTaskCommand(
            task_id=task_id,
            account_id=actor.account_id,
            assigned_member_id=payload.assigned_member_id,
            expected_version=payload.expected_version,
        ),
    )


@router.post("/api/v1/task-changes/{change_id}/undo", response_model=TaskResponse)
async def undo_change_endpoint(
    change_id: UUID, payload: ExpectedVersionRequest, request: Request
) -> TaskResponse:
    actor = _actor(request)
    return await _run_task_command(
        request,
        undo_change.execute,
        UndoChangeCommand(
            change_id=change_id,
            account_id=actor.account_id,
            expected_version=payload.expected_version,
        ),
    )
