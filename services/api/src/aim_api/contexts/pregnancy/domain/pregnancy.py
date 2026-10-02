from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from enum import StrEnum
from uuid import UUID

from aim_api.contexts.pregnancy.domain.fact import FactEvidence, FactRecordResult, PregnancyFacts
from aim_api.contexts.pregnancy.domain.errors import DueDateOutOfRange
from aim_api.contexts.pregnancy.domain.gestational_age import GestationalAge, gestational_age
from aim_api.contexts.pregnancy.domain.pregnancy_dates import last_menstrual_period_from_due_date

#: 能保存的最大孕周：42 周 0 天。
MAX_GESTATION_DAYS = 42 * 7


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

    def change_due_date(self, new_due_date: date, *, today: date) -> date:
        """改预产期，返回旧值。

        范围按今天对应的孕周判断：0 周 0 天到 42 周 0 天（含两端）。
        `gestational_age` 会把负值截成 0，所以这里用原始天数判断。
        """
        elapsed = (today - last_menstrual_period_from_due_date(new_due_date)).days
        if elapsed < 0:
            raise DueDateOutOfRange("这个日期算出来还没到孕期，请检查一下")
        if elapsed > MAX_GESTATION_DAYS:
            raise DueDateOutOfRange("这个日期算出来已经超过 42 周了，请检查一下")
        previous = self.due_date
        self.due_date = new_due_date
        self.updated_at = datetime.now(UTC)
        return previous

    def record_fact(
        self, evidence: FactEvidence, *, now: datetime | None = None
    ) -> FactRecordResult:
        result = self.facts.record(evidence, now=now)
        self.updated_at = now or datetime.now(UTC)
        return result
