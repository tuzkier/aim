from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from aim_api.contexts.records.domain.errors import RecordValidationError
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility

NOW = datetime(2026, 10, 12, 3, 0, tzinfo=UTC)


def make(structured_data: dict, *, content: str | None = None,
         visibility: RecordVisibility = RecordVisibility.family) -> Record:
    return Record.create(
        record_id=uuid4(),
        pregnancy_id=uuid4(),
        family_id=uuid4(),
        author_account_id=uuid4(),
        record_type=RecordType.hospital_trip,
        occurred_at=NOW,
        visibility=visibility,
        title="我们出发去医院了",
        content=content,
        structured_data=structured_data,
        now=NOW,
    )


class TestHospitalTrip:
    @pytest.mark.parametrize(
        "reason", ["contractions", "water_broke", "bleeding", "fetal_movement", "scheduled", "other"]
    )
    def test_every_reason_is_accepted(self, reason):
        assert make({"reason": reason}).structured_data == {"reason": reason}

    def test_unknown_reason_is_rejected(self):
        with pytest.raises(RecordValidationError):
            make({"reason": "bored"})

    def test_reason_is_required(self):
        with pytest.raises(RecordValidationError):
            make({})

    def test_a_linked_contraction_must_be_a_lowercase_uuid(self):
        linked = str(uuid4())
        make({"reason": "contractions", "contraction_record_id": linked})
        with pytest.raises(RecordValidationError):
            make({"reason": "contractions", "contraction_record_id": linked.upper()})
        with pytest.raises(RecordValidationError):
            make({"reason": "contractions", "contraction_record_id": "abc"})

    def test_note_is_at_most_200_characters(self):
        make({"reason": "other"}, content="字" * 200)
        with pytest.raises(RecordValidationError):
            make({"reason": "other"}, content="字" * 201)

    def test_it_cannot_be_private(self):
        with pytest.raises(RecordValidationError):
            make({"reason": "contractions"}, visibility=RecordVisibility.private)

    def test_unknown_fields_are_rejected(self):
        with pytest.raises(RecordValidationError):
            make({"reason": "other", "eta": "10 分钟"})
