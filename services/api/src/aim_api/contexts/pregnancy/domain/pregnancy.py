from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from enum import StrEnum
from uuid import UUID

from aim_api.contexts.pregnancy.domain.fact import FactEvidence, FactRecordResult, PregnancyFacts
from aim_api.contexts.pregnancy.domain.errors import DueDateOutOfRange
from aim_api.contexts.pregnancy.domain.gestational_age import GestationalAge, gestational_age
from aim_api.contexts.pregnancy.domain.pregnancy_dates import last_menstrual_period_from_due_date
from aim_api.platform.business_time import beijing_today

#: 能保存的最大孕周：42 周 0 天。
MAX_GESTATION_DAYS = 42 * 7


class PregnancyStatus(StrEnum):
    active = "active"
    completed = "completed"
    paused = "paused"
    postpartum = "postpartum"


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
    birth_date: date | None = None
    birth_revision: UUID | None = None

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
        day = on_date or beijing_today()
        if self.birth_date is not None:
            day = min(day, self.birth_date)
        return gestational_age(self.due_date, day)

    def postpartum_days(self, today: date | None = None) -> int | None:
        return max(0, ((today or beijing_today()) - self.birth_date).days) if self.birth_date else None

    @staticmethod
    def validate_birth_date(value: date, today: date) -> None:
        if not 0 <= (today - value).days <= 365:
            raise ValueError("请填写过去一年内的真实分娩日期，不能晚于今天")

    def record_birth(self, value: date, *, revision: UUID, today: date) -> None:
        self.validate_birth_date(value, today)
        if self.birth_date is not None:
            raise ValueError("已记录分娩，请使用日期修正")
        self.birth_date = value
        self.birth_revision = revision
        self.status = PregnancyStatus.postpartum
        self.updated_at = datetime.now(UTC)

    def correct_birth_date(self, value: date, *, today: date) -> None:
        self.validate_birth_date(value, today)
        if self.birth_date is None:
            raise ValueError("尚未记录分娩")
        self.birth_date = value
        self.updated_at = datetime.now(UTC)

    def retract_birth(self) -> None:
        if self.birth_date is None:
            raise ValueError("尚未记录分娩")
        self.birth_date = None
        self.birth_revision = None
        self.status = PregnancyStatus.active
        self.updated_at = datetime.now(UTC)

    def change_due_date(self, new_due_date: date, *, today: date) -> date:
        """改预产期，返回旧值。

        范围按今天对应的孕周判断：0 周 0 天到 42 周 0 天（含两端）。
        `gestational_age` 会把负值截成 0，所以这里用原始天数判断。
        """
        elapsed = ((self.birth_date or today) - last_menstrual_period_from_due_date(new_due_date)).days
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
