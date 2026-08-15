from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from aim_api.contexts.pregnancy.domain.pregnancy_dates import (
    last_menstrual_period_from_due_date,
)


@dataclass(frozen=True, slots=True)
class GestationalAge:
    weeks: int
    days: int

    def __post_init__(self) -> None:
        if self.weeks < 0 or not 0 <= self.days <= 6:
            raise ValueError("gestational age must be non-negative and days must be 0..6")


def gestational_age(due_date: date, on_date: date) -> GestationalAge:
    estimated_lmp = last_menstrual_period_from_due_date(due_date)
    elapsed_days = max((on_date - estimated_lmp).days, 0)
    weeks, days = divmod(elapsed_days, 7)
    return GestationalAge(weeks=weeks, days=days)
