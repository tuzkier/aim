from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from aim_api.contexts.records.domain.errors import RecordValidationError
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility

NOW = datetime(2026, 10, 9, 21, 0, tzinfo=UTC)


def valid(**overrides) -> dict:
    data = {
        "duration_seconds": 1920,
        "count": 10,
        "target": 10,
        "outcome": "reached",
        "taps": [30, 200, 400, 600, 800, 1000, 1200, 1500, 1700, 1920],
    }
    data.update(overrides)
    return data


def make(structured_data: dict) -> Record:
    return Record.create(
        record_id=uuid4(),
        pregnancy_id=uuid4(),
        family_id=uuid4(),
        author_account_id=uuid4(),
        record_type=RecordType.fetal_movement,
        occurred_at=NOW,
        visibility=RecordVisibility.family,
        title="数胎动 10 次 · 32 分钟",
        content=None,
        structured_data=structured_data,
        now=NOW,
    )


class TestFetalMovement:
    def test_a_reached_session_is_valid(self):
        assert make(valid()).structured_data["outcome"] == "reached"

    def test_an_under_session_needs_two_full_hours(self):
        six_taps = [10, 20, 30, 40, 50, 60]
        make(valid(outcome="under", count=6, duration_seconds=7200, taps=six_taps))
        with pytest.raises(RecordValidationError):
            make(valid(outcome="under", count=6, duration_seconds=7199, taps=six_taps))

    def test_under_must_have_fewer_than_target(self):
        with pytest.raises(RecordValidationError):
            make(valid(outcome="under", duration_seconds=7200))

    def test_reached_needs_at_least_target(self):
        with pytest.raises(RecordValidationError):
            make(valid(count=9, taps=[1, 2, 3, 4, 5, 6, 7, 8, 9]))

    def test_a_stopped_session_has_no_count_requirement(self):
        make(valid(outcome="stopped", count=0, duration_seconds=90, taps=[]))

    @pytest.mark.parametrize("duration", [-1, 10801, 12.5, True, "60"])
    def test_duration_must_be_an_integer_within_three_hours(self, duration):
        with pytest.raises(RecordValidationError):
            make(valid(duration_seconds=duration))

    @pytest.mark.parametrize("count", [-1, 201, True, "10"])
    def test_count_must_be_an_integer_in_range(self, count):
        with pytest.raises(RecordValidationError):
            make(valid(count=count))

    @pytest.mark.parametrize("target", [6, 12, True, None])
    def test_target_is_fixed_at_ten(self, target):
        with pytest.raises(RecordValidationError):
            make(valid(target=target))

    def test_unknown_outcome_is_rejected(self):
        with pytest.raises(RecordValidationError):
            make(valid(outcome="normal"))

    def test_taps_must_match_count(self):
        with pytest.raises(RecordValidationError):
            make(valid(taps=[1, 2, 3]))

    def test_taps_must_not_go_backwards_or_past_the_duration(self):
        with pytest.raises(RecordValidationError):
            make(valid(taps=[30, 20, 400, 600, 800, 1000, 1200, 1500, 1700, 1920]))
        with pytest.raises(RecordValidationError):
            make(valid(taps=[30, 200, 400, 600, 800, 1000, 1200, 1500, 1700, 1921]))

    def test_equal_neighbouring_taps_are_allowed(self):
        """秒级取整后，相邻两次点按可能落在同一秒。"""
        make(valid(taps=[30, 30, 400, 600, 800, 1000, 1200, 1500, 1700, 1920]))
