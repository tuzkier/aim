from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.dialects import postgresql
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from aim_api.contexts.family.adapters.outbound.persistence.repositories import (
    SqlAlchemyFamilyRepository,
)
from aim_api.contexts.family.application.ports import PersistenceConflict
from aim_api.contexts.planning.adapters.outbound.persistence.models import (
    PlanTemplateSeedModel,
    PregnancyPlanModel,
    TaskChangeModel,
    TaskModel,
)
from aim_api.contexts.planning.domain.plan import PregnancyPlan
from aim_api.contexts.planning.domain.task import ActorType, Task, TaskSourceType
from aim_api.contexts.planning.domain.task_change import TaskChange
from aim_api.contexts.planning.domain.task_status import TaskStatus, TaskVersionConflict
from aim_api.contexts.pregnancy.adapters.outbound.persistence.repositories import (
    SqlAlchemyPregnancyRepository,
)


class SqlAlchemyPlanningRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def add_plan(self, plan: PregnancyPlan) -> None:
        self.session.add(
            PregnancyPlanModel(
                id=plan.id,
                pregnancy_id=plan.pregnancy_id,
                version=plan.version,
                created_at=plan.created_at,
                updated_at=plan.updated_at,
            )
        )
        await self.session.flush()

    async def add_task(self, task: Task) -> None:
        self.session.add(_to_task_model(task))

    async def get_plan(self, pregnancy_id: UUID) -> PregnancyPlan | None:
        model = await self.session.scalar(
            select(PregnancyPlanModel).where(PregnancyPlanModel.pregnancy_id == pregnancy_id)
        )
        if model is None:
            return None
        task_models = (
            await self.session.scalars(select(TaskModel).where(TaskModel.plan_id == model.id))
        ).all()
        plan = PregnancyPlan(
            id=model.id,
            pregnancy_id=model.pregnancy_id,
            version=model.version,
            created_at=model.created_at,
            updated_at=model.updated_at,
        )
        for task_model in task_models:
            plan.add_task(_to_task(task_model))
        return plan

    async def seeded_template_ids(self, plan_id: UUID) -> set[str]:
        rows = await self.session.scalars(
            select(PlanTemplateSeedModel.template_id).where(
                PlanTemplateSeedModel.plan_id == plan_id
            )
        )
        return set(rows.all())

    async def try_seed(self, plan_id: UUID, template_id: str, now: datetime) -> bool:
        # 并发的两次 sync 只有一方能插入成功，另一方据此跳过建任务。
        result = await self.session.execute(
            postgresql.insert(PlanTemplateSeedModel)
            .values(plan_id=plan_id, template_id=template_id, seeded_at=now)
            .on_conflict_do_nothing()
            .returning(PlanTemplateSeedModel.template_id)
        )
        return result.scalar_one_or_none() is not None

    async def get_task(self, task_id: UUID) -> Task | None:
        model = await self.session.get(TaskModel, task_id)
        return _to_task(model) if model else None

    async def delete_task(self, task_id: UUID) -> None:
        """硬删除。任务的 task_changes 会随外键级联一并删除，审计轨迹不保留。"""
        model = await self.session.get(TaskModel, task_id)
        if model is not None:
            await self.session.delete(model)

    async def save_task_change(self, task: Task, change: TaskChange, expected_version: int) -> None:
        result = await self.session.execute(
            update(TaskModel)
            .where(TaskModel.id == task.id, TaskModel.version == expected_version)
            .values(
                status=task.status.value,
                changed_by_actor_type=task.changed_by_actor_type.value,
                changed_by_actor_id=task.changed_by_actor_id,
                version=task.version,
                scheduled_for=task.scheduled_for,
                due_at=task.due_at,
                assigned_member_id=task.assigned_member_id,
                updated_at=task.updated_at,
            )
        )
        if result.rowcount != 1:
            raise TaskVersionConflict("task version has changed")
        self.session.add(
            TaskChangeModel(
                id=change.id,
                task_id=change.task_id,
                operation=change.operation,
                before_json=_encode_snapshot(change.before),
                after_json=_encode_snapshot(change.after),
                version_before=change.version_before,
                version_after=change.version_after,
                changed_by_actor_type=change.changed_by_actor_type,
                changed_by_actor_id=change.changed_by_actor_id,
                created_at=change.created_at,
            )
        )

    async def get_change(self, change_id: UUID) -> TaskChange | None:
        model = await self.session.get(TaskChangeModel, change_id)
        return _to_change(model) if model else None

    async def get_change_by_version(
        self, task_id: UUID, version_after: int
    ) -> TaskChange | None:
        """某次写入产生的那条变更。命令只返回 Task，撤销却需要变更本身。"""
        model = await self.session.scalar(
            select(TaskChangeModel).where(
                TaskChangeModel.task_id == task_id,
                TaskChangeModel.version_after == version_after,
            )
        )
        return _to_change(model) if model else None


class SqlAlchemyPlanningUnitOfWork:
    def __init__(self, session: AsyncSession) -> None:
        self.repository = SqlAlchemyPlanningRepository(session)
        self.family_membership = SqlAlchemyFamilyRepository(session)
        self.pregnancy_ownership = SqlAlchemyPregnancyRepository(session)
        self._session = session

    async def commit(self) -> None:
        try:
            await self._session.commit()
        except IntegrityError as error:
            await self._session.rollback()
            raise PersistenceConflict("planning persistence constraint failed") from error

    async def rollback(self) -> None:
        await self._session.rollback()


def _to_task_model(task: Task) -> TaskModel:
    return TaskModel(
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
        # 只在新建时用到这个转换，此刻的改动人就是创建人。
        created_by_actor_type=task.changed_by_actor_type.value,
        created_by_actor_id=task.changed_by_actor_id,
        version=task.version,
        scheduled_for=task.scheduled_for,
        due_at=task.due_at,
        assigned_member_id=task.assigned_member_id,
        created_at=task.created_at,
        updated_at=task.updated_at,
    )


def _to_task(model: TaskModel) -> Task:
    return Task(
        id=model.id,
        plan_id=model.plan_id,
        pregnancy_id=model.pregnancy_id,
        title=model.title,
        description=model.description,
        status=TaskStatus(model.status),
        source_type=TaskSourceType(model.source_type),
        source_id=model.source_id,
        changed_by_actor_type=ActorType(model.changed_by_actor_type),
        changed_by_actor_id=model.changed_by_actor_id,
        version=model.version,
        scheduled_for=model.scheduled_for,
        due_at=model.due_at,
        assigned_member_id=model.assigned_member_id,
        created_at=model.created_at,
        updated_at=model.updated_at,
    )


def _encode_snapshot(snapshot: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in snapshot.items():
        if isinstance(value, (datetime, UUID)):
            result[key] = value.isoformat() if isinstance(value, datetime) else str(value)
        else:
            result[key] = value
    return result


def _decode_snapshot(snapshot: dict[str, Any]) -> dict[str, Any]:
    result = dict(snapshot)
    for key in ("scheduled_for", "due_at"):
        if result.get(key) is not None and isinstance(result[key], str):
            result[key] = datetime.fromisoformat(result[key])
    if result.get("assigned_member_id") is not None and isinstance(
        result["assigned_member_id"], str
    ):
        result["assigned_member_id"] = UUID(result["assigned_member_id"])
    return result


def _to_change(model: TaskChangeModel) -> TaskChange:
    return TaskChange(
        id=model.id,
        task_id=model.task_id,
        operation=model.operation,
        before=_decode_snapshot(model.before_json),
        after=_decode_snapshot(model.after_json),
        version_before=model.version_before,
        version_after=model.version_after,
        changed_by_actor_type=model.changed_by_actor_type,
        changed_by_actor_id=model.changed_by_actor_id,
        created_at=model.created_at,
    )
