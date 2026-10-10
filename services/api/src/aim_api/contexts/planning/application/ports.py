from __future__ import annotations

from datetime import datetime
from typing import Protocol
from uuid import UUID

from aim_api.contexts.planning.domain.plan import PregnancyPlan
from aim_api.contexts.planning.domain.task import Task
from aim_api.contexts.planning.domain.task_change import TaskChange


class PlanningRepositoryPort(Protocol):
    async def add_plan(self, plan: PregnancyPlan) -> None: ...

    async def add_task(self, task: Task) -> None: ...

    async def get_plan(self, pregnancy_id: UUID) -> PregnancyPlan | None: ...

    async def get_task(self, task_id: UUID) -> Task | None: ...

    async def seeded_template_ids(self, plan_id: UUID) -> set[str]: ...

    async def try_seed(self, plan_id: UUID, template_id: str, now: datetime) -> bool:
        """记下这个计划生成过该模板。已记过（含并发的另一方刚记下）返回 False。"""
        ...

    async def delete_task(self, task_id: UUID) -> None: ...

    async def save_task_change(
        self, task: Task, change: TaskChange, expected_version: int
    ) -> None: ...

    async def get_change(self, change_id: UUID) -> TaskChange | None: ...

    async def get_change_by_version(
        self, task_id: UUID, version_after: int
    ) -> TaskChange | None: ...


class FamilyMembershipPort(Protocol):
    async def is_active_member(self, family_id: UUID, account_id: UUID) -> bool: ...


class PregnancyOwnershipPort(Protocol):
    async def get_pregnancy(self, pregnancy_id: UUID): ...


class PlanningUnitOfWork(Protocol):
    repository: PlanningRepositoryPort
    family_membership: FamilyMembershipPort
    pregnancy_ownership: PregnancyOwnershipPort

    async def commit(self) -> None: ...

    async def rollback(self) -> None: ...
