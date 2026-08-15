from datetime import date

from aim_api.contexts.pregnancy.domain.pregnancy_dates import (
    due_date_from_last_menstrual_period,
    last_menstrual_period_from_due_date,
)


def test_standard_pregnancy_dates_are_280_days_apart() -> None:
    last_menstrual_period = date(2026, 4, 11)
    due_date = date(2027, 1, 16)

    assert due_date_from_last_menstrual_period(last_menstrual_period) == due_date
    assert last_menstrual_period_from_due_date(due_date) == last_menstrual_period
