from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from aim_api.contexts.planning.application.commands.complete_task import (
    CompleteTaskCommand,
)
from aim_api.contexts.planning.application.commands.complete_task import (
    execute as complete_task,
)
from aim_api.contexts.planning.application.commands.create_task import (
    CreateTaskCommand,
)
from aim_api.contexts.planning.application.commands.create_task import execute as create_task
from aim_api.contexts.planning.application.commands.schedule_task import (
    ScheduleTaskCommand,
)
from aim_api.contexts.planning.application.commands.schedule_task import (
    execute as schedule_task,
)
from aim_api.contexts.planning.domain.task import ActorType, Task, TaskSourceType
from aim_api.contexts.planning.domain.task_status import TaskVersionConflict


class FakeRepository:
    def __init__(self, task: Task) -> None:
        self.task = task
        self.changes = []
        self.created_tasks = []

    async def get_task(self, task_id):
        return self.task if task_id == self.task.id else None

    async def save_task_change(self, task, change, expected_version):
        if task.version != expected_version + 1:
            raise TaskVersionConflict("stale task version")
        self.changes.append(change)

    async def add_task(self, task):
        self.created_tasks.append(task)

    async def get_plan(self, pregnancy_id):
        return type("PlanRef", (), {"id": self.task.plan_id})()


class FakeMembership:
    async def is_active_member(self, family_id, account_id):
        return True


class FakePregnancyOwnership:
    def __init__(self, task: Task) -> None:
        self.pregnancy_id = task.pregnancy_id

    async def get_pregnancy(self, pregnancy_id):
        return type("PregnancyRef", (), {"family_id": uuid4()})()


class FakeUow:
    def __init__(self, task):
        self.repository = FakeRepository(task)
        self.family_membership = FakeMembership()
        self.pregnancy_ownership = FakePregnancyOwnership(task)
        self.committed = False

    async def commit(self):
        self.committed = True

    async def rollback(self):
        pass


def _task() -> Task:
    return Task.create(
        task_id=uuid4(),
        plan_id=uuid4(),
        pregnancy_id=uuid4(),
        title="检查材料",
        source_type=TaskSourceType.template,
        source_id="week-18-materials",
        changed_by_actor_type=ActorType.account,
        changed_by_actor_id=uuid4(),
        now=datetime(2026, 8, 14, tzinfo=UTC),
    )


@pytest.mark.asyncio
async def test_commands_use_expected_version_and_commit_change() -> None:
    uow = FakeUow(_task())
    task = uow.repository.task
    await schedule_task(
        ScheduleTaskCommand(
            task_id=task.id,
            account_id=uuid4(),
            expected_version=1,
            scheduled_for=datetime(2026, 8, 19, 9, 30, tzinfo=UTC),
        ),
        uow,
    )
    assert uow.committed is True
    assert len(uow.repository.changes) == 1


@pytest.mark.asyncio
async def test_complete_command_rejects_stale_version() -> None:
    uow = FakeUow(_task())
    with pytest.raises(TaskVersionConflict):
        await complete_task(
            CompleteTaskCommand(
                task_id=uow.repository.task.id, account_id=uuid4(), expected_version=9
            ),
            uow,
        )


@pytest.mark.asyncio
async def test_create_task_links_record_source_and_commits() -> None:
    uow = FakeUow(_task())
    account_id = uuid4()
    record_id = uuid4()

    created = await create_task(
        CreateTaskCommand(
            pregnancy_id=uow.repository.task.pregnancy_id,
            account_id=account_id,
            title="根据产检结果复查",
            description="两周后带报告复诊",
            due_at=datetime(2026, 8, 30, 9, 0, tzinfo=UTC),
            source_type=TaskSourceType.record,
            source_id=str(record_id),
        ),
        uow,
    )

    assert uow.committed is True
    assert uow.repository.created_tasks == [created]
    assert created.plan_id == uow.repository.task.plan_id
    assert created.pregnancy_id == uow.repository.task.pregnancy_id
    assert created.source_type is TaskSourceType.record
    assert created.source_id == str(record_id)
    assert created.changed_by_actor_type is ActorType.account
    assert created.changed_by_actor_id == account_id
    assert created.due_at == datetime(2026, 8, 30, 9, 0, tzinfo=UTC)
