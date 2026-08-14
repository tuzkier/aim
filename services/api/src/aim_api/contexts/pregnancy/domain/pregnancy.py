from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from enum import StrEnum
from uuid import UUID

from aim_api.contexts.pregnancy.domain.fact import FactEvidence, FactRecordResult, PregnancyFacts
from aim_api.contexts.pregnancy.domain.gestational_age import GestationalAge, gestational_age


class PregnancyStatus(StrEnum):
    active = "active"
    completed = "completed"
    paused = "paused"


@dataclass(slots=True)
class Pregnancy:
    id: UUID
    family_id: UUID
    due_date: date
    created_by: UUID
    status: PregnancyStatus
    created_at: datetime
    updated_at: datetime
    facts: PregnancyFacts = field(default_factory=PregnancyFacts)

    @classmethod
    def create(
        cls,
        pregnancy_id: UUID,
        family_id: UUID,
        due_date: date,
        created_by: UUID,
        *,
        now: datetime | None = None,
    ) -> Pregnancy:
        if due_date.year < 2000:
            raise ValueError("due date is not valid")
        created = now or datetime.now(UTC)
        return cls(
            id=pregnancy_id,
            family_id=family_id,
            due_date=due_date,
            created_by=created_by,
            status=PregnancyStatus.active,
            created_at=created,
            updated_at=created,
        )

    def gestational_age(self, on_date: date | None = None) -> GestationalAge:
        return gestational_age(self.due_date, on_date or datetime.now(UTC).date())

    def record_fact(
        self, evidence: FactEvidence, *, now: datetime | None = None
    ) -> FactRecordResult:
        result = self.facts.record(evidence, now=now)
        self.updated_at = now or datetime.now(UTC)
        return result
