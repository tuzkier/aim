"""孕周推进时续上本周任务。

只生成覆盖当前孕周、且这个计划从未生成过的模板——种子表记着「生成过」，
用户删掉的任务因此不会复活；跳过的孕周不补，过时的提醒不如不提醒。
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID, uuid4

from aim_api.contexts.guidance.application.queries.get_guidance import initial_plan_items
from aim_api.contexts.planning.application.ports import PlanningUnitOfWork
from aim_api.contexts.planning.domain.task import ActorType, Task, TaskSourceType

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class SyncWeekTasksCommand:
    pregnancy_id: UUID
    as_of: date


async def execute(command: SyncWeekTasksCommand, uow: PlanningUnitOfWork) -> int:
    """返回新建的任务数。不做权限校验——调用方必须先确认读者有权看这个孕期。"""
    pregnancy = await uow.pregnancy_ownership.get_pregnancy(command.pregnancy_id)
    if pregnancy is None:
        return 0
    plan = await uow.repository.get_plan(command.pregnancy_id)
    if plan is None:
        return 0
    week = pregnancy.gestational_age(command.as_of).weeks
    seeded = await uow.repository.seeded_template_ids(plan.id)
    # 生成时间与种子时间记真实时间；截止日仍按 as_of（接口传的就是服务器今天）推算。
    now = datetime.now(UTC)
    created = 0
    for item in initial_plan_items(week):
        if item.id in seeded or not await uow.repository.try_seed(plan.id, item.id, now):
            continue
        task = Task.create(
            task_id=uuid4(),
            plan_id=plan.id,
            pregnancy_id=command.pregnancy_id,
            title=item.title,
            description=item.summary,
            source_type=TaskSourceType.template,
            source_id=item.id,
            changed_by_actor_type=ActorType.system,
            changed_by_actor_id=None,
            due_at=datetime.combine(
                command.as_of + timedelta(days=item.due_in_days), time(9, 0), tzinfo=UTC
            ),
            assigned_member_id=None,
            now=now,
        )
        await uow.repository.add_task(task)
        created += 1
    if created:
        await uow.commit()
    return created


async def sync_quietly(uow: PlanningUnitOfWork, pregnancy_id: UUID, as_of: date) -> None:
    """读取前续上本周任务。失败只记日志——续任务不能让待办页打不开。

    收 uow 而不是 session：应用层不依赖持久化适配器，调用方本来就建好了 uow，
    sync 与随后的读取共用同一个 session。
    """
    try:
        await execute(SyncWeekTasksCommand(pregnancy_id=pregnancy_id, as_of=as_of), uow)
    except Exception:
        logger.exception("week task sync failed for pregnancy %s", pregnancy_id)
        await uow.rollback()
