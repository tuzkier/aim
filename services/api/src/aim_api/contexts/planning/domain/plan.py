from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from uuid import UUID


@dataclass(slots=True)
class PregnancyPlan:
    id: UUID
    pregnancy_id: UUID
    version: int
    created_at: datetime
    updated_at: datetime
    tasks: list[object] = field(default_factory=list)

    @classmethod
    def create(
        cls,
        plan_id: UUID,
        pregnancy_id: UUID,
        *,
        now: datetime | None = None,
    ) -> PregnancyPlan:
        created = now or datetime.now(UTC)
        return cls(
            id=plan_id,
            pregnancy_id=pregnancy_id,
            version=1,
            created_at=created,
            updated_at=created,
        )

    def add_task(self, task: object) -> None:
        self.tasks.append(task)
