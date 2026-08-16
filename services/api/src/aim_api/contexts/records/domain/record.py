from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any
from uuid import UUID

from aim_api.contexts.records.domain.errors import RecordAccessDenied, RecordValidationError


class RecordType(StrEnum):
    symptom = "symptom"
    checkup = "checkup"
    note = "note"


class RecordVisibility(StrEnum):
    family = "family"
    private = "private"


@dataclass(slots=True)
class Record:
    id: UUID
    pregnancy_id: UUID
    family_id: UUID
    author_account_id: UUID
    record_type: RecordType
    occurred_at: datetime
    visibility: RecordVisibility
    title: str | None
    content: str | None
    structured_data: dict[str, Any]
    attachment_refs: list[str]
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None

    @classmethod
    def create(
        cls,
        *,
        record_id: UUID,
        pregnancy_id: UUID,
        family_id: UUID,
        author_account_id: UUID,
        record_type: RecordType,
        occurred_at: datetime,
        visibility: RecordVisibility,
        structured_data: dict[str, Any],
        title: str | None = None,
        content: str | None = None,
        attachment_refs: list[str] | None = None,
        now: datetime | None = None,
    ) -> Record:
        if not isinstance(structured_data, dict):
            raise RecordValidationError("structured_data must be a JSON object")
        cls._validate_payload(record_type, structured_data, content)
        created_at = now or datetime.now(UTC)
        return cls(
            id=record_id,
            pregnancy_id=pregnancy_id,
            family_id=family_id,
            author_account_id=author_account_id,
            record_type=record_type,
            occurred_at=occurred_at,
            visibility=visibility,
            title=title,
            content=content,
            structured_data=dict(structured_data),
            attachment_refs=list(attachment_refs or []),
            created_at=created_at,
            updated_at=created_at,
            deleted_at=None,
        )

    def assert_can_mutate(self, account_id: UUID) -> None:
        if self.author_account_id != account_id:
            raise RecordAccessDenied("only the record author can mutate it")

    def soft_delete(self, account_id: UUID, *, now: datetime | None = None) -> None:
        self.assert_can_mutate(account_id)
        deleted_at = now or datetime.now(UTC)
        self.deleted_at = deleted_at
        self.updated_at = deleted_at

    @staticmethod
    def _validate_payload(
        record_type: RecordType,
        structured_data: dict[str, Any],
        content: str | None,
    ) -> None:
        if record_type is RecordType.symptom:
            symptoms = structured_data.get("symptoms")
            severity = structured_data.get("severity")
            if (
                not isinstance(symptoms, list)
                or not symptoms
                or not all(isinstance(symptom, str) and symptom.strip() for symptom in symptoms)
            ):
                raise RecordValidationError("symptom records require a non-empty symptoms string list")
            if isinstance(severity, bool) or not isinstance(severity, int) or not 1 <= severity <= 5:
                raise RecordValidationError("symptom severity must be an integer from 1 through 5")
            note = structured_data.get("note")
            if note is not None and not isinstance(note, str):
                raise RecordValidationError("symptom note must be a string when provided")
            return

        if record_type is RecordType.checkup:
            for field in ("hospital", "exam_items", "result", "doctor_advice"):
                value = structured_data.get(field)
                if not isinstance(value, str):
                    raise RecordValidationError(f"checkup {field} must be a string")
            return

        if record_type is RecordType.note:
            if not isinstance(content, str) or not content.strip():
                raise RecordValidationError("note records require non-empty content")
            return

        raise RecordValidationError(f"unsupported record type: {record_type}")
