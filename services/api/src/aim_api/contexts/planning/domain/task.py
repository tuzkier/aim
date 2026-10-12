from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any
from uuid import UUID, uuid4

from aim_api.contexts.planning.domain.task_change import TaskChange
from aim_api.contexts.planning.domain.task_status import (
    InvalidTaskTransition,
    TaskStatus,
    TaskVersionConflict,
)


class TaskSourceType(StrEnum):
    template = "template"
    user = "user"
    agent = "agent"
    doctor_requirement = "doctor_requirement"
    family_member = "family_member"
    record = "record"


class ActorType(StrEnum):
    account = "account"
    agent = "agent"
    system = "system"


@dataclass(slots=True)
class Task:
    id: UUID
    plan_id: UUID
    pregnancy_id: UUID
    title: str
    description: str | None
    status: TaskStatus
    source_type: TaskSourceType
    source_id: str | None
    changed_by_actor_type: ActorType
    changed_by_actor_id: UUID | None
    version: int
    scheduled_for: datetime | None
    due_at: datetime | None
    assigned_member_id: UUID | None
    created_at: datetime
    updated_at: datetime

    @classmethod
    def create(
        cls,
        *,
        task_id: UUID,
        plan_id: UUID,
        pregnancy_id: UUID,
        title: str,
        source_type: TaskSourceType,
        source_id: str | None,
        changed_by_actor_type: ActorType,
        changed_by_actor_id: UUID | None,
        description: str | None = None,
        due_at: datetime | None = None,
        assigned_member_id: UUID | None = None,
        now: datetime | None = None,
    ) -> Task:
        cleaned_title = title.strip()
        if not cleaned_title:
            raise ValueError("task title cannot be empty")
        created = now or datetime.now(UTC)
        return cls(
            id=task_id,
            plan_id=plan_id,
            pregnancy_id=pregnancy_id,
            title=cleaned_title,
            description=description,
            status=TaskStatus.todo,
            source_type=source_type,
            source_id=source_id,
            changed_by_actor_type=changed_by_actor_type,
            changed_by_actor_id=changed_by_actor_id,
            version=1,
            scheduled_for=None,
            due_at=due_at,
            assigned_member_id=assigned_member_id,
            created_at=created,
            updated_at=created,
        )

    def schedule(
        self,
        scheduled_for: datetime,
        *,
        expected_version: int,
        changed_by_actor_type: ActorType | None = None,
        changed_by_actor_id: UUID | None = None,
    ) -> TaskChange:
        self._assert_version(expected_version)
        if self.status in (TaskStatus.done, TaskStatus.cancelled):
            raise InvalidTaskTransition("done task cannot be scheduled")
        return self._change(
            operation="schedule",
            expected_version=expected_version,
            changes={
                "status": TaskStatus.scheduled.value,
                "scheduled_for": scheduled_for,
                "due_at": scheduled_for,
            },
            changed_by_actor_type=changed_by_actor_type,
            changed_by_actor_id=changed_by_actor_id,
        )

    def complete(
        self,
        *,
        expected_version: int,
        changed_by_actor_type: ActorType | None = None,
        changed_by_actor_id: UUID | None = None,
    ) -> TaskChange:
        self._assert_version(expected_version)
        if self.status in (TaskStatus.done, TaskStatus.cancelled):
            raise InvalidTaskTransition("task is already done")
        return self._change(
            operation="complete",
            expected_version=expected_version,
            changes={"status": TaskStatus.done.value},
            changed_by_actor_type=changed_by_actor_type,
            changed_by_actor_id=changed_by_actor_id,
        )

    def delay(
        self,
        due_at: datetime,
        *,
        expected_version: int,
        changed_by_actor_type: ActorType | None = None,
        changed_by_actor_id: UUID | None = None,
    ) -> TaskChange:
        self._assert_version(expected_version)
        if self.status in (TaskStatus.done, TaskStatus.cancelled):
            raise InvalidTaskTransition("done task cannot be delayed")
        return self._change(
            operation="delay",
            expected_version=expected_version,
            changes={"due_at": due_at},
            changed_by_actor_type=changed_by_actor_type,
            changed_by_actor_id=changed_by_actor_id,
        )

    def assign(
        self,
        assigned_member_id: UUID | None,
        *,
        expected_version: int,
        changed_by_actor_type: ActorType | None = None,
        changed_by_actor_id: UUID | None = None,
    ) -> TaskChange:
        self._assert_version(expected_version)
        if self.status is TaskStatus.cancelled:
            raise InvalidTaskTransition("不再适用的待办不能重新分工")
        return self._change(
            operation="assign",
            expected_version=expected_version,
            changes={"assigned_member_id": assigned_member_id},
            changed_by_actor_type=changed_by_actor_type,
            changed_by_actor_id=changed_by_actor_id,
        )

    def restore(
        self,
        *,
        expected_version: int,
        changed_by_actor_type: ActorType | None = None,
        changed_by_actor_id: UUID | None = None,
    ) -> TaskChange:
        self._assert_version(expected_version)
        if self.status is not TaskStatus.done:
            raise InvalidTaskTransition("only a done task can be restored")
        return self._change(
            operation="restore",
            expected_version=expected_version,
            changes={"status": TaskStatus.todo.value},
            changed_by_actor_type=changed_by_actor_type,
            changed_by_actor_id=changed_by_actor_id,
        )

    def undo_change(
        self,
        change: TaskChange,
        *,
        expected_version: int,
        changed_by_actor_type: ActorType | None = None,
        changed_by_actor_id: UUID | None = None,
        allow_birth_cancel: bool = False,
    ) -> TaskChange:
        self._assert_version(expected_version)
        if change.operation == "birth_cancel" and not allow_birth_cancel:
            raise InvalidTaskTransition("阶段切换产生的结束只能通过撤回分娩恢复")
        if change.task_id != self.id or change.version_after != expected_version:
            raise InvalidTaskTransition("task change is not the current change")
        return self._change(
            operation="undo",
            expected_version=expected_version,
            changes=change.before,
            changed_by_actor_type=changed_by_actor_type,
            changed_by_actor_id=changed_by_actor_id,
        )

    def _change(
        self,
        *,
        operation: str,
        expected_version: int,
        changes: dict[str, Any],
        changed_by_actor_type: ActorType | None,
        changed_by_actor_id: UUID | None,
    ) -> TaskChange:
        if self.version != expected_version:
            raise TaskVersionConflict(
                f"task version is {self.version}, expected {expected_version}"
            )
        before = self._snapshot()
        for name, value in changes.items():
            setattr(self, name, TaskStatus(value) if name == "status" else value)
        self.version += 1
        self.updated_at = datetime.now(UTC)
        if changed_by_actor_type is not None:
            self.changed_by_actor_type = changed_by_actor_type
            if changed_by_actor_type is ActorType.system and changed_by_actor_id is None:
                self.changed_by_actor_id = None
        if changed_by_actor_id is not None:
            self.changed_by_actor_id = changed_by_actor_id
        after = self._snapshot()
        return TaskChange(
            id=uuid4(),
            task_id=self.id,
            operation=operation,
            before=before,
            after=after,
            version_before=expected_version,
            version_after=self.version,
            changed_by_actor_type=self.changed_by_actor_type.value,
            changed_by_actor_id=self.changed_by_actor_id,
            created_at=self.updated_at,
        )

    def cancel_for_birth(self, *, expected_version: int, revision: UUID) -> TaskChange:
        self._assert_version(expected_version)
        if self.status in (TaskStatus.done, TaskStatus.cancelled):
            raise InvalidTaskTransition("已结束的待办不能再次标为不适用")
        change = self._change(operation="birth_cancel", expected_version=expected_version,
            changes={"status": TaskStatus.cancelled.value}, changed_by_actor_type=ActorType.system,
            changed_by_actor_id=None)
        change.after["birth_revision"] = str(revision)
        return change

    def _assert_version(self, expected_version: int) -> None:
        if self.version != expected_version:
            raise TaskVersionConflict(
                f"task version is {self.version}, expected {expected_version}"
            )

    def _snapshot(self) -> dict[str, Any]:
        return {
            "status": self.status.value,
            "scheduled_for": self.scheduled_for,
            "due_at": self.due_at,
            "assigned_member_id": self.assigned_member_id,
        }
