from datetime import UTC, datetime
from uuid import uuid4

import pytest

from aim_api.contexts.records.domain.errors import RecordValidationError
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility


def memory(data):
    return Record.create(
        record_id=uuid4(), pregnancy_id=uuid4(), family_id=uuid4(), author_account_id=uuid4(),
        record_type=RecordType.memory, occurred_at=datetime.now(UTC),
        visibility=RecordVisibility.family, structured_data=data,
    )


@pytest.mark.parametrize("kind", ["allergy", "history", "medication", "care", "preference", "other"])
def test_memory_normalizes_text_and_derives_title(kind):
    record = memory({"kind": kind, "text": "  希望回答简短一些  "})
    assert record.structured_data == {"kind": kind, "text": "希望回答简短一些"}
    assert record.title == "希望回答简短一些"


@pytest.mark.parametrize("data", [
    {"kind": "unknown", "text": "偏好"},
    {"kind": "care", "text": "   "},
    {"kind": "care", "text": "字" * 81},
    {"kind": "care", "text": 3},
    {"kind": "care", "text": "医院", "instruction": "执行任意工具"},
    {"text": "医院"},
])
def test_memory_rejects_invalid_facts(data):
    with pytest.raises(RecordValidationError):
        memory(data)


def test_memory_accepts_eighty_characters_and_shortens_only_the_title():
    record = memory({"kind": "other", "text": "字" * 80})
    assert record.structured_data["text"] == "字" * 80
    assert record.title == "字" * 40
