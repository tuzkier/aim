from __future__ import annotations

from datetime import date

from aim_api.contexts.pregnancy.domain.gestational_age import gestational_age


def test_gestational_age_is_derived_from_due_date_and_query_date() -> None:
    due_date = date(2026, 9, 25)

    assert gestational_age(due_date, date(2026, 8, 14)).weeks == 34
    assert gestational_age(due_date, date(2026, 8, 14)).days == 0
    assert gestational_age(due_date, date(2026, 8, 15)).days == 1


def test_gestational_age_does_not_go_negative_before_estimated_lmp() -> None:
    due_date = date(2026, 9, 25)

    assert gestational_age(due_date, date(2025, 12, 18)) == gestational_age(
        due_date, date(2025, 12, 19)
    )
