from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any
from uuid import UUID

from aim_api.contexts.planning.domain.task_status import TaskStatus


@dataclass(frozen=True, slots=True)
class TaskChange:
    id: UUID
    task_id: UUID
    operation: str
    before: dict[str, Any]
    after: dict[str, Any]
    version_before: int
    version_after: int
    changed_by_actor_type: str
    changed_by_actor_id: UUID | None
    created_at: datetime

    @property
    def before_status(self) -> TaskStatus:
        return TaskStatus(self.before["status"])

    @property
    def after_status(self) -> TaskStatus:
        return TaskStatus(self.after["status"])
