from datetime import UTC, date, datetime, timedelta
from uuid import uuid4
import pytest

from aim_api.contexts.pregnancy.domain.pregnancy import Pregnancy, PregnancyStatus
from aim_api.platform.business_time import beijing_today, add_months


def pregnancy():
    return Pregnancy.create(uuid4(), uuid4(), date(2026, 11, 1), uuid4())


def test_beijing_day_switches_at_utc_sixteen():
    assert beijing_today(datetime(2026, 10, 11, 15, 59, tzinfo=UTC)) == date(2026, 10, 11)
    assert beijing_today(datetime(2026, 10, 11, 16, 0, tzinfo=UTC)) == date(2026, 10, 12)


def test_calendar_months_use_the_original_birthday_and_clamp_month_ends():
    assert add_months(date(2026, 1, 31), 1) == date(2026, 2, 28)
    assert add_months(date(2026, 1, 31), 2) == date(2026, 3, 31)
    assert add_months(date(2024, 1, 31), 1) == date(2024, 2, 29)


def test_birth_freezes_gestational_age_and_tracks_actual_postpartum_days():
    p = pregnancy(); revision = uuid4(); birthday = date(2026, 10, 12)
    at_birth = p.gestational_age(birthday)
    p.record_birth(birthday, revision=revision, today=birthday)
    assert p.status is PregnancyStatus.postpartum
    assert p.birth_revision == revision
    assert p.gestational_age(birthday + timedelta(days=42)) == at_birth
    assert p.postpartum_days(birthday) == 0
    assert p.postpartum_days(birthday + timedelta(days=42)) == 42
    p.retract_birth()
    assert p.status is PregnancyStatus.active
    assert p.birth_date is None and p.birth_revision is None


def test_invalid_or_second_birth_is_not_silently_replaced():
    p = pregnancy(); today = date(2026, 10, 12)
    for invalid in (today + timedelta(days=1), today - timedelta(days=366)):
        with pytest.raises(ValueError): p.record_birth(invalid, revision=uuid4(), today=today)
    p.record_birth(today, revision=uuid4(), today=today)
    with pytest.raises(ValueError): p.record_birth(today, revision=uuid4(), today=today)


def test_correcting_the_birth_date_preserves_the_revision():
    p = pregnancy(); today = date(2026, 10, 12); revision = uuid4()
    p.record_birth(today, revision=revision, today=today)
    p.correct_birth_date(today - timedelta(days=2), today=today)
    assert p.birth_revision == revision
    assert p.postpartum_days(today) == 2
