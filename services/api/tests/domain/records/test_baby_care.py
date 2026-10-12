from datetime import UTC, datetime, timedelta
from uuid import uuid4
import pytest
from aim_api.contexts.records.domain.baby_care import validate_care, normalize_care
from aim_api.contexts.records.domain.errors import RecordValidationError

NOW = datetime(2026, 10, 12, 12, tzinfo=UTC)
START = NOW - timedelta(hours=2)
BABY = str(uuid4())


def test_feeding_preserves_fractional_observed_amount_and_does_not_invent_unknowns():
    data = {"baby_id": BABY, "mode": "formula", "volume_ml": 60.5}
    validate_care("feeding", data, START, now=NOW)
    assert normalize_care("feeding", data, START)["volume_ml"] == 60.5
    assert normalize_care("feeding", {"baby_id": BABY}, START) == {"baby_id": BABY, "mode": "unknown"}


@pytest.mark.parametrize("data", [{"volume_ml": True}, {"volume_ml": 0}, {"volume_ml": 2001}, {"volume_ml": float("inf")},
    {"volume_ml": 50, "mode": "breast"}, {"duration_minutes": False}, {"duration_minutes": 181}, {"side": "both", "mode": "formula"}])
def test_invalid_feeding_values_are_rejected(data):
    with pytest.raises(RecordValidationError): validate_care("feeding", {"baby_id": BABY, **data}, START, now=NOW)


def test_sleep_duration_is_derived_and_timezone_is_normalized():
    data = {"baby_id": BABY, "ended_at": NOW.astimezone().isoformat(), "duration_seconds": 999999}
    validate_care("sleep", data, START, now=NOW)
    normalized = normalize_care("sleep", data, START)
    assert normalized["duration_seconds"] == 7200
    assert normalized["ended_at"] == NOW.isoformat()


@pytest.mark.parametrize("end", [START, START - timedelta(seconds=1), NOW + timedelta(seconds=1), START + timedelta(hours=25)])
def test_sleep_order_future_and_maximum_duration(end):
    with pytest.raises(RecordValidationError): validate_care("sleep", {"baby_id": BABY, "ended_at": end.isoformat()}, START, now=NOW)


def test_invalid_or_naive_times_and_foreign_id_formats_are_rejected():
    with pytest.raises(RecordValidationError): validate_care("feeding", {"baby_id": BABY}, START.replace(tzinfo=None), now=NOW)
    with pytest.raises(RecordValidationError): validate_care("sleep", {"baby_id": BABY, "ended_at": "2026-10-12T10:00:00"}, START, now=NOW)
    with pytest.raises(RecordValidationError): validate_care("diaper", {"baby_id": "not-a-baby", "kind": "wet"}, START, now=NOW)
    for invalid in ["unknown", [], True]:
        with pytest.raises(RecordValidationError): validate_care("diaper", {"baby_id": BABY, "kind": invalid}, START, now=NOW)
