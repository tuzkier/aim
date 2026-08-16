from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest

from aim_api.contexts.records.domain.errors import RecordAccessDenied, RecordValidationError
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility


NOW = datetime(2026, 8, 16, 9, 0, tzinfo=UTC)


def make_record(**overrides: object) -> Record:
    values: dict[str, object] = {
        "record_id": UUID("00000000-0000-0000-0000-000000000001"),
        "pregnancy_id": UUID("00000000-0000-0000-0000-000000000002"),
        "family_id": UUID("00000000-0000-0000-0000-000000000003"),
        "author_account_id": UUID("00000000-0000-0000-0000-000000000004"),
        "record_type": RecordType.symptom,
        "occurred_at": NOW,
        "visibility": RecordVisibility.family,
        "structured_data": {"symptoms": ["nausea"], "severity": 3, "note": "早晨明显"},
        "now": NOW,
    }
    values.update(overrides)
    return Record.create(**values)  # type: ignore[arg-type]


def test_record_creation_keeps_user_entered_symptom_payload() -> None:
    record = make_record()

    assert record.record_type is RecordType.symptom
    assert record.structured_data == {"symptoms": ["nausea"], "severity": 3, "note": "早晨明显"}
    assert record.attachment_refs == []


def test_record_rejects_invalid_symptom_severity() -> None:
    with pytest.raises(RecordValidationError):
        make_record(structured_data={"symptoms": ["nausea"], "severity": 6})


def test_record_requires_complete_checkup_payload() -> None:
    with pytest.raises(RecordValidationError):
        make_record(record_type=RecordType.checkup, structured_data={"hospital": "市妇幼"})


def test_note_record_requires_non_empty_content() -> None:
    with pytest.raises(RecordValidationError):
        make_record(record_type=RecordType.note, content="  ", structured_data={})


def test_only_author_can_edit_or_soft_delete_record() -> None:
    author_id = UUID("00000000-0000-0000-0000-000000000004")
    other_account_id = uuid4()
    record = make_record(author_account_id=author_id)

    record.assert_can_mutate(author_id)
    with pytest.raises(RecordAccessDenied):
        record.assert_can_mutate(other_account_id)

    record.soft_delete(author_id, now=NOW)
    assert record.deleted_at == NOW


def test_record_task_source_type_is_supported() -> None:
    from aim_api.contexts.planning.domain.task import TaskSourceType

    assert TaskSourceType.record.value == "record"
