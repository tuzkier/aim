from __future__ import annotations

from uuid import uuid4

import pytest

from aim_api.contexts.planning.application.commands.create_task import (
    CreateTaskCommand,
)
from aim_api.contexts.planning.application.commands.create_task import execute as create_task
from aim_api.contexts.planning.application.commands.delete_task import (
    DeleteTaskCommand,
)
from aim_api.contexts.planning.application.commands.delete_task import execute as delete_task
from aim_api.contexts.planning.domain.errors import PlanningAccessDenied
from aim_api.contexts.planning.domain.task import ActorType, Task, TaskSourceType

FAMILY_ID = uuid4()
PREGNANCY_ID = uuid4()
ACCOUNT_ID = uuid4()
PLAN_ID = uuid4()


def make_task() -> Task:
    return Task.create(
        task_id=uuid4(),
        plan_id=PLAN_ID,
        pregnancy_id=PREGNANCY_ID,
        title="产检预约",
        description=None,
        source_type=TaskSourceType.user,
        source_id=None,
        changed_by_actor_type=ActorType.account,
        changed_by_actor_id=ACCOUNT_ID,
    )


class FakeRepository:
    def __init__(self, task: Task | None = None) -> None:
        self.task = task
        self.created_tasks: list[Task] = []
        self.deleted_task_ids: list = []

    async def get_task(self, task_id):
        if self.task is not None and task_id == self.task.id:
            return self.task
        return None

    async def add_task(self, task):
        self.created_tasks.append(task)

    async def delete_task(self, task_id):
        self.deleted_task_ids.append(task_id)

    async def get_plan(self, pregnancy_id):
        return type("PlanRef", (), {"id": PLAN_ID})()


class FakeMembership:
    def __init__(self, *, active: bool = True) -> None:
        self.active = active

    async def is_active_member(self, family_id, account_id):
        return self.active


class FakePregnancyOwnership:
    def __init__(self, *, pregnancy_id=PREGNANCY_ID) -> None:
        self.pregnancy_id = pregnancy_id

    async def get_pregnancy(self, pregnancy_id):
        if pregnancy_id != self.pregnancy_id:
            return None
        return type("PregnancyRef", (), {"family_id": FAMILY_ID, "id": pregnancy_id})()


class FakeUnitOfWork:
    def __init__(self, repository, membership=None, ownership=None) -> None:
        self.repository = repository
        self.family_membership = membership or FakeMembership()
        self.pregnancy_ownership = ownership or FakePregnancyOwnership()
        self.committed = False

    async def commit(self):
        self.committed = True

    async def rollback(self):
        pass


class TestAgentAuthoredTasks:
    """Agent 建的任务必须标成 agent 来源，时间线才会显示「Agent 调整」标记。"""

    @pytest.mark.asyncio
    async def test_create_task_records_the_agent_as_actor(self):
        repository = FakeRepository()
        uow = FakeUnitOfWork(repository)

        task = await create_task(
            CreateTaskCommand(
                pregnancy_id=PREGNANCY_ID,
                account_id=ACCOUNT_ID,
                title="产检预约",
                changed_by_actor_type=ActorType.agent,
            ),
            uow,
        )

        assert task.changed_by_actor_type is ActorType.agent
        assert repository.created_tasks == [task]
        assert uow.committed

    @pytest.mark.asyncio
    async def test_create_task_still_defaults_to_the_account(self):
        """既有的公开 API 不传这个参数，行为必须保持不变。"""
        uow = FakeUnitOfWork(FakeRepository())

        task = await create_task(
            CreateTaskCommand(
                pregnancy_id=PREGNANCY_ID,
                account_id=ACCOUNT_ID,
                title="产检预约",
            ),
            uow,
        )

        assert task.changed_by_actor_type is ActorType.account


class TestDeleteTask:
    """撤销「Agent 新建待办」走的是任务删除——undo_operation 做的是字段级还原，
    新建没有可还原的前值，撤销不了。"""

    @pytest.mark.asyncio
    async def test_deletes_a_task_within_the_pregnancy(self):
        task = make_task()
        repository = FakeRepository(task)
        uow = FakeUnitOfWork(repository)

        await delete_task(
            DeleteTaskCommand(
                task_id=task.id,
                pregnancy_id=PREGNANCY_ID,
                account_id=ACCOUNT_ID,
            ),
            uow,
        )

        assert repository.deleted_task_ids == [task.id]
        assert uow.committed

    @pytest.mark.asyncio
    async def test_rejects_a_task_from_another_pregnancy(self):
        task = make_task()
        repository = FakeRepository(task)
        uow = FakeUnitOfWork(repository)

        with pytest.raises(PlanningAccessDenied):
            await delete_task(
                DeleteTaskCommand(
                    task_id=task.id,
                    pregnancy_id=uuid4(),
                    account_id=ACCOUNT_ID,
                ),
                uow,
            )

        assert repository.deleted_task_ids == []

    @pytest.mark.asyncio
    async def test_rejects_a_non_member(self):
        task = make_task()
        repository = FakeRepository(task)
        uow = FakeUnitOfWork(repository, membership=FakeMembership(active=False))

        with pytest.raises(PlanningAccessDenied):
            await delete_task(
                DeleteTaskCommand(
                    task_id=task.id,
                    pregnancy_id=PREGNANCY_ID,
                    account_id=ACCOUNT_ID,
                ),
                uow,
            )

        assert repository.deleted_task_ids == []

    @pytest.mark.asyncio
    async def test_missing_task_is_not_an_error(self):
        """撤销可能被重放（toast 点两次、网络重试），删除要幂等。"""
        repository = FakeRepository(None)
        uow = FakeUnitOfWork(repository)

        await delete_task(
            DeleteTaskCommand(
                task_id=uuid4(),
                pregnancy_id=PREGNANCY_ID,
                account_id=ACCOUNT_ID,
            ),
            uow,
        )

        assert repository.deleted_task_ids == []
