from __future__ import annotations

from datetime import date, timedelta

STANDARD_GESTATION_DAYS = 280


def due_date_from_last_menstrual_period(last_menstrual_period: date) -> date:
    return last_menstrual_period + timedelta(days=STANDARD_GESTATION_DAYS)


def last_menstrual_period_from_due_date(due_date: date) -> date:
    return due_date - timedelta(days=STANDARD_GESTATION_DAYS)
