from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta


@dataclass(frozen=True, slots=True)
class GestationalAge:
    weeks: int
    days: int

    def __post_init__(self) -> None:
        if self.weeks < 0 or not 0 <= self.days <= 6:
            raise ValueError("gestational age must be non-negative and days must be 0..6")


def gestational_age(due_date: date, on_date: date) -> GestationalAge:
    estimated_lmp = due_date - timedelta(days=280)
    elapsed_days = max((on_date - estimated_lmp).days, 0)
    weeks, days = divmod(elapsed_days, 7)
    return GestationalAge(weeks=weeks, days=days)
