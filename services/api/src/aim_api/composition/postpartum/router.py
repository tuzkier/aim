"""分娩、宝宝与计划的同一事务；不把历史孕期待办伪装成已完成。"""
from datetime import UTC, date, datetime, timedelta
import json
from typing import Literal
from uuid import UUID, uuid4

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field
from sqlalchemy import select

from aim_api.contexts.babies.adapters.outbound.persistence.models import BabyModel
from aim_api.contexts.babies.adapters.outbound.persistence.repositories import SqlAlchemyBabyRepository
from aim_api.contexts.family.adapters.outbound.persistence.repositories import SqlAlchemyFamilyRepository
from aim_api.contexts.family.domain.events import FamilyEvent, FamilyEventKind
from aim_api.contexts.guidance.application.queries.get_guidance import CONTENT_ROOT
from aim_api.contexts.planning.adapters.outbound.persistence.repositories import SqlAlchemyPlanningRepository
from aim_api.contexts.planning.adapters.outbound.persistence.models import TaskChangeModel
from aim_api.contexts.planning.domain.plan import PregnancyPlan
from aim_api.contexts.planning.domain.task import Task, TaskSourceType, ActorType
from aim_api.contexts.planning.domain.task_status import TaskStatus, TaskVersionConflict
from aim_api.contexts.pregnancy.adapters.outbound.persistence.models import PregnancyModel
from aim_api.contexts.pregnancy.adapters.outbound.persistence.repositories import SqlAlchemyPregnancyRepository
from aim_api.contexts.pregnancy.adapters.inbound.http.router import PregnancyResponse, _response as pregnancy_response
from aim_api.contexts.records.adapters.outbound.persistence.models import RecordModel
from aim_api.platform.auth.context import authenticate_active
from aim_api.platform.business_time import beijing_today, add_months, at_nine
from aim_api.platform.http.errors import ConflictError, ForbiddenError, NotFoundError

router = APIRouter(tags=["postpartum"])


def care_content() -> dict:
    return json.loads((CONTENT_ROOT / "postpartum/care.json").read_text())


class BabyInput(BaseModel):
    name: str = Field(default="宝宝", max_length=80)
    birth_date: date | None = None
    sex: Literal["male", "female", "unknown"] = "unknown"
    birth_weight_grams: int | None = Field(default=None, strict=True, ge=1, le=20000)


class BirthInput(BaseModel):
    birth_date: date
    babies: list[BabyInput] = Field(default_factory=list, max_length=8)


class BirthDateInput(BaseModel):
    birth_date: date


class BabyResponse(BaseModel):
    id: UUID
    pregnancy_id: UUID
    family_id: UUID
    name: str
    birth_date: date
    sex: str
    birth_weight_grams: int | None
    age_days: int


class BabyListResponse(BaseModel):
    babies: list[BabyResponse]


class BirthResponse(BaseModel):
    pregnancy: PregnancyResponse
    babies: list[BabyResponse]


def baby_response(model: BabyModel) -> BabyResponse:
    return BabyResponse(id=model.id, pregnancy_id=model.pregnancy_id, family_id=model.family_id,
                        name=model.name, birth_date=model.birth_date, sex=model.sex,
                        birth_weight_grams=model.birth_weight_grams,
                        age_days=max(0, (beijing_today() - model.birth_date).days))


async def checked_pregnancy(session, pregnancy_id: UUID, actor_id: UUID, *, lock=False):
    query = select(PregnancyModel).where(PregnancyModel.id == pregnancy_id)
    if lock:
        query = query.with_for_update()
    row = await session.scalar(query)
    if row is None:
        raise NotFoundError("找不到这段孕期")
    if not await SqlAlchemyFamilyRepository(session).is_active_member(row.family_id, actor_id):
        raise ForbiddenError("不能访问这个家庭的宝宝与分娩信息")
    return row


async def snapshot(session, row) -> BirthResponse:
    pregnancy = await SqlAlchemyPregnancyRepository(session).get_pregnancy(row.id)
    babies = await SqlAlchemyBabyRepository(session).list_active(row.id, row.family_id)
    return BirthResponse(pregnancy=pregnancy_response(pregnancy), babies=[baby_response(b) for b in babies])


def prefix(row) -> str:
    return f"postpartum.{row.birth_revision}."


async def plan_for(session, row):
    repository = SqlAlchemyPlanningRepository(session)
    plan = await repository.get_plan(row.id)
    if plan is None:
        now = datetime.now(UTC)
        plan = PregnancyPlan(id=uuid4(), pregnancy_id=row.id, version=1, created_at=now, updated_at=now)
        await repository.add_plan(plan)
    return repository, plan


def schedule_definitions(row, babies) -> list[dict]:
    content = care_content()
    result = []
    for item in content["care"]:
        result.append({**item, "key": prefix(row) + "mother." + item["id"],
                       "due": at_nine(row.birth_date + timedelta(days=item["days"]))})
    for baby in babies:
        base = prefix(row) + str(baby.id) + "."
        for item in content["documents"]:
            result.append({**item, "key": base + "document." + item["id"], "title": baby.name + " · " + item["title"],
                           "due": at_nine(baby.birth_date + timedelta(days=item["days"]))})
        for item in content["vaccines"]:
            if item["months"] > 2:
                continue
            result.append({**item, "key": base + "vaccine." + item["id"],
                           "title": baby.name + " · 核对" + item["title"] + "安排",
                           "due": at_nine(add_months(baby.birth_date, item["months"]))})
    # 情绪节点由本人页面判定，不借家庭待办完成状态披露私有自评活动。
    return result


async def seed_schedule(session, row, babies):
    repository, plan = await plan_for(session, row)
    now = datetime.now(UTC)
    for item in schedule_definitions(row, babies):
        if await repository.try_seed(plan.id, item["key"], now):
            await repository.add_task(Task.create(task_id=uuid4(), plan_id=plan.id, pregnancy_id=row.id,
                title=item["title"], description=item["summary"], due_at=item["due"],
                source_type=TaskSourceType.template, source_id=item["key"],
                changed_by_actor_type=ActorType.system, changed_by_actor_id=None))


async def reschedule_defaults(session, row, babies):
    repository, plan = await plan_for(session, row)
    due = {item["key"]: item["due"] for item in schedule_definitions(row, babies)}
    for task in plan.tasks:
        if task.source_id in due and task.status not in (TaskStatus.done, TaskStatus.cancelled) and task.changed_by_actor_type is ActorType.system:
            if task.due_at == due[task.source_id]:
                continue
            version = task.version
            change = task.schedule(due[task.source_id], expected_version=version, changed_by_actor_type=ActorType.system)
            try:
                await repository.save_task_change(task, change, version)
            except TaskVersionConflict as error:
                await session.rollback()
                raise ConflictError("有待办刚被更新，请刷新后重试日期修正") from error


async def event(session, row, actor_id, kind, payload):
    await SqlAlchemyFamilyRepository(session).add_event(FamilyEvent.new(row.family_id, kind, actor=actor_id, payload=payload))


def validate_baby_date(birthday: date, row):
    if birthday < row.birth_date or birthday > beijing_today():
        raise ConflictError("宝宝生日不能早于分娩日期或晚于今天，请核对")


@router.get("/api/v1/content/postpartum")
async def get_content():
    return care_content()


@router.get("/api/v1/pregnancies/{pregnancy_id}/babies", response_model=BabyListResponse)
async def list_babies(pregnancy_id: UUID, request: Request):
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        row = await checked_pregnancy(session, pregnancy_id, actor.account_id)
        values = await SqlAlchemyBabyRepository(session).list_active(row.id, row.family_id)
        return BabyListResponse(babies=[baby_response(b) for b in values])


@router.post("/api/v1/pregnancies/{pregnancy_id}/birth", response_model=BirthResponse)
async def record_birth(pregnancy_id: UUID, body: BirthInput, request: Request):
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        row = await checked_pregnancy(session, pregnancy_id, actor.account_id, lock=True)
        pregnancy = await SqlAlchemyPregnancyRepository(session).get_pregnancy(row.id)
        babies = SqlAlchemyBabyRepository(session)
        if row.birth_date is not None:
            if row.birth_date == body.birth_date:
                existing = await babies.list_active(row.id, row.family_id)
                requested = [(b.name.strip() or "宝宝", b.birth_date or body.birth_date, b.sex, b.birth_weight_grams) for b in body.babies]
                actual = [(b.name, b.birth_date, b.sex, b.birth_weight_grams) for b in existing]
                if requested == actual:
                    return await snapshot(session, row)
                raise ConflictError("已记录分娩，档案与这次请求不同，请刷新后核对")
            raise ConflictError("已记录分娩，请使用日期修正")
        try:
            pregnancy.record_birth(body.birth_date, revision=uuid4(), today=beijing_today())
        except ValueError as error:
            raise ConflictError(str(error)) from error
        row.birth_date, row.birth_revision, row.status = pregnancy.birth_date, pregnancy.birth_revision, pregnancy.status.value
        row.updated_at = pregnancy.updated_at
        for value in body.babies:
            birthday = value.birth_date or row.birth_date
            validate_baby_date(birthday, row)
            await babies.add(pregnancy_id=row.id, family_id=row.family_id, revision=row.birth_revision,
                actor=actor.account_id, name=value.name, birth_date=birthday, sex=value.sex, weight=value.birth_weight_grams)
        await session.flush()
        repository, plan = await plan_for(session, row)
        try:
            for task in plan.tasks:
                if task.source_type is TaskSourceType.template and not (task.source_id or "").startswith("postpartum.") and task.status not in (TaskStatus.done, TaskStatus.cancelled):
                    version = task.version
                    change = task.cancel_for_birth(expected_version=version, revision=row.birth_revision)
                    await repository.save_task_change(task, change, version)
            await seed_schedule(session, row, await babies.list_active(row.id, row.family_id))
            await event(session, row, actor.account_id, FamilyEventKind.birth_recorded, {"date": row.birth_date.isoformat()})
            await session.commit()
        except TaskVersionConflict as error:
            await session.rollback()
            raise ConflictError("有待办刚被更新，请重试记录分娩") from error
        return await snapshot(session, row)


@router.patch("/api/v1/pregnancies/{pregnancy_id}/birth", response_model=BirthResponse)
async def correct_birth(pregnancy_id: UUID, body: BirthDateInput, request: Request):
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        row = await checked_pregnancy(session, pregnancy_id, actor.account_id, lock=True)
        pregnancy = await SqlAlchemyPregnancyRepository(session).get_pregnancy(row.id)
        old = row.birth_date
        try:
            pregnancy.correct_birth_date(body.birth_date, today=beijing_today())
        except ValueError as error:
            raise ConflictError(str(error)) from error
        values = await SqlAlchemyBabyRepository(session).list_active(row.id, row.family_id)
        for baby in values:
            new_day = body.birth_date if baby.birth_date == old else baby.birth_date
            if new_day < body.birth_date:
                raise ConflictError("分娩日期不能晚于宝宝生日，请先核对宝宝档案")
            await assert_no_earlier_care(session, baby.id, new_day)
            baby.birth_date = new_day
            baby.updated_at = datetime.now(UTC)
        row.birth_date = pregnancy.birth_date
        row.updated_at = pregnancy.updated_at
        await reschedule_defaults(session, row, values)
        await event(session, row, actor.account_id, FamilyEventKind.birth_date_changed,
                    {"from": old.isoformat(), "to": row.birth_date.isoformat()})
        await session.commit()
        return await snapshot(session, row)


async def assert_no_earlier_care(session, baby_id: UUID, day: date):
    rows = (await session.scalars(select(RecordModel).where(RecordModel.record_type.in_(["feeding", "diaper", "sleep"]),
        RecordModel.structured_data["baby_id"].as_string() == str(baby_id)))).all()
    if any(beijing_today(record.occurred_at) < day for record in rows):
        raise ConflictError("已有照护记录早于新生日，请先核对记录时间")


@router.post("/api/v1/pregnancies/{pregnancy_id}/babies", response_model=BabyResponse, status_code=201)
async def add_baby(pregnancy_id: UUID, body: BabyInput, request: Request):
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        row = await checked_pregnancy(session, pregnancy_id, actor.account_id, lock=True)
        if row.birth_date is None:
            raise ConflictError("请先记录分娩日期")
        repository = SqlAlchemyBabyRepository(session)
        existing = await repository.list_active(row.id, row.family_id)
        if len(existing) >= 8:
            raise ConflictError("这段孕期最多记录 8 个宝宝档案")
        birthday = body.birth_date or row.birth_date
        validate_baby_date(birthday, row)
        baby = await repository.add(pregnancy_id=row.id, family_id=row.family_id, revision=row.birth_revision,
            actor=actor.account_id, name=body.name, birth_date=birthday, sex=body.sex, weight=body.birth_weight_grams)
        await session.flush()
        await seed_schedule(session, row, [baby])
        await session.commit()
        return baby_response(baby)


@router.patch("/api/v1/pregnancies/{pregnancy_id}/babies/{baby_id}", response_model=BabyResponse)
async def update_baby(pregnancy_id: UUID, baby_id: UUID, body: BabyInput, request: Request):
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        row = await checked_pregnancy(session, pregnancy_id, actor.account_id, lock=True)
        baby = await SqlAlchemyBabyRepository(session).get_active(baby_id, row.id, row.family_id)
        if baby is None:
            raise NotFoundError("找不到宝宝档案")
        birthday = body.birth_date or baby.birth_date
        validate_baby_date(birthday, row)
        await assert_no_earlier_care(session, baby.id, birthday)
        baby.name, baby.birth_date, baby.sex, baby.birth_weight_grams = body.name.strip() or "宝宝", birthday, body.sex, body.birth_weight_grams
        baby.updated_at = datetime.now(UTC)
        await reschedule_defaults(session, row, await SqlAlchemyBabyRepository(session).list_active(row.id, row.family_id))
        await session.commit()
        return baby_response(baby)


@router.delete("/api/v1/pregnancies/{pregnancy_id}/birth", response_model=PregnancyResponse)
async def retract_birth(pregnancy_id: UUID, request: Request):
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        row = await checked_pregnancy(session, pregnancy_id, actor.account_id, lock=True)
        if row.birth_date is None:
            raise ConflictError("尚未记录分娩")
        babies = await SqlAlchemyBabyRepository(session).list_active(row.id, row.family_id)
        ids = [str(b.id) for b in babies]
        care = await session.scalar(select(RecordModel.id).where(RecordModel.pregnancy_id == row.id,
            ((RecordModel.record_type.in_(["feeding", "diaper", "sleep"]) & RecordModel.structured_data["baby_id"].as_string().in_(ids)) |
             ((RecordModel.record_type == "epds") & RecordModel.structured_data["period"].as_string().in_(["postpartum_2w", "postpartum_6w"])))).limit(1))
        repository, plan = await plan_for(session, row)
        generated = [task for task in plan.tasks if (task.source_id or "").startswith(prefix(row))]
        if care is not None or any(t.changed_by_actor_type is not ActorType.system or t.status is TaskStatus.done for t in generated):
            raise ConflictError("已有产后记录或已处理的安排，不能撤回；请核对并修正日期")
        try:
            for task in generated:
                if task.status not in (TaskStatus.done, TaskStatus.cancelled):
                    version = task.version
                    change = task.cancel_for_birth(expected_version=version, revision=row.birth_revision)
                    await repository.save_task_change(task, change, version)
            for task in plan.tasks:
                if task in generated or task.status is not TaskStatus.cancelled:
                    continue
                latest = await session.scalar(select(TaskChangeModel).where(TaskChangeModel.task_id == task.id,
                    TaskChangeModel.version_after == task.version, TaskChangeModel.operation == "birth_cancel"))
                if latest and latest.after_json.get("birth_revision") == str(row.birth_revision):
                    change = await repository.get_change(latest.id)
                    version = task.version
                    restored = task.undo_change(change, expected_version=version, changed_by_actor_type=ActorType.system,
                                                allow_birth_cancel=True)
                    await repository.save_task_change(task, restored, version)
            for baby in babies:
                baby.archived_at = datetime.now(UTC)
            await event(session, row, actor.account_id, FamilyEventKind.birth_retracted, {"date": row.birth_date.isoformat()})
            pregnancy = await SqlAlchemyPregnancyRepository(session).get_pregnancy(row.id)
            pregnancy.retract_birth()
            row.status, row.birth_date, row.birth_revision, row.updated_at = pregnancy.status.value, None, None, pregnancy.updated_at
            await session.commit()
        except TaskVersionConflict as error:
            await session.rollback()
            raise ConflictError("有待办刚被更新，请重试撤回") from error
        return pregnancy_response(pregnancy)
