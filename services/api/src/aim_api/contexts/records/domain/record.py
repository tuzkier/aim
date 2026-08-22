from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any, ClassVar
from uuid import UUID

from aim_api.contexts.records.domain.errors import RecordAccessDenied, RecordValidationError


class RecordType(StrEnum):
    symptom = "symptom"
    checkup = "checkup"
    note = "note"
    question = "question"
    checklist = "checklist"


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
        if attachment_refs:
            raise RecordValidationError("attachment references are reserved until uploads are supported")
        cls._validate_payload(record_type, structured_data, content)
        structured_data = cls._with_defaults(record_type, structured_data)
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

    def assert_attachment_refs_reserved(self) -> None:
        if self.attachment_refs:
            raise RecordValidationError("attachment references are reserved until uploads are supported")

    def is_visible_to(self, account_id: UUID) -> bool:
        return self.deleted_at is None and (
            self.visibility is RecordVisibility.family or self.author_account_id == account_id
        )

    def soft_delete(self, account_id: UUID, *, now: datetime | None = None) -> None:
        self.assert_can_mutate(account_id)
        deleted_at = now or datetime.now(UTC)
        self.deleted_at = deleted_at
        self.updated_at = deleted_at

    # 可计算的产检指标。范围刻意放宽——只挡明显的输入错误，
    # 不替医生判断什么算异常。
    CHECKUP_METRIC_RANGES: ClassVar[dict[str, tuple[float, float]]] = {
        "weight_kg": (30.0, 200.0),
        "systolic": (60.0, 250.0),
        "diastolic": (30.0, 150.0),
        "fasting_glucose": (2.0, 20.0),
        "hemoglobin": (50.0, 200.0),
    }

    @classmethod
    def _validate_checkup_metrics(cls, metrics: Any) -> None:
        if metrics is None:
            return
        if not isinstance(metrics, dict):
            raise RecordValidationError("checkup metrics must be a JSON object")
        for key, value in metrics.items():
            bounds = cls.CHECKUP_METRIC_RANGES.get(key)
            if bounds is None:
                # 未知指标名要挡住——否则错别字会静默变成一条永远没人看的数据。
                raise RecordValidationError(f"unsupported checkup metric: {key}")
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise RecordValidationError(f"checkup metric {key} must be a number")
            low, high = bounds
            if not low <= float(value) <= high:
                raise RecordValidationError(
                    f"checkup metric {key} is outside the plausible range {low}-{high}"
                )
        systolic = metrics.get("systolic")
        diastolic = metrics.get("diastolic")
        if (
            isinstance(systolic, (int, float))
            and isinstance(diastolic, (int, float))
            and float(diastolic) >= float(systolic)
        ):
            raise RecordValidationError("diastolic pressure must be below systolic")

    @staticmethod
    def _with_defaults(record_type: RecordType, structured_data: dict[str, Any]) -> dict[str, Any]:
        """把可选状态字段的默认值显式写进去。

        消费方（列表、统计、客户端）读到的永远是完整结构，
        不必各自记住「没有 answered 就等于未回答」。
        """
        if record_type is RecordType.question:
            return {"answered": False, **structured_data}
        if record_type is RecordType.checklist:
            return {"done": False, **structured_data}
        return structured_data

    @classmethod
    def _validate_payload(
        cls,
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
            cls._validate_checkup_metrics(structured_data.get("metrics"))
            return

        if record_type is RecordType.note:
            if not isinstance(content, str) or not content.strip():
                raise RecordValidationError("note records require non-empty content")
            return

        # 「想问医生」：问题本身就是一句话，答案与已答状态放结构化字段。
        if record_type is RecordType.question:
            if not isinstance(content, str) or not content.strip():
                raise RecordValidationError("question records require non-empty content")
            answered = structured_data.get("answered", False)
            if not isinstance(answered, bool):
                raise RecordValidationError("question answered must be a boolean")
            answer = structured_data.get("answer")
            if answer is not None and not isinstance(answer, str):
                raise RecordValidationError("question answer must be a string when provided")
            return

        # 「办事指南」「待产准备」共用：内容库给条目，这里只存勾选状态。
        if record_type is RecordType.checklist:
            for field in ("collection", "item_id"):
                value = structured_data.get(field)
                if not isinstance(value, str) or not value.strip():
                    raise RecordValidationError(f"checklist {field} must be a non-empty string")
            done = structured_data.get("done", False)
            if not isinstance(done, bool):
                raise RecordValidationError("checklist done must be a boolean")
            return

        raise RecordValidationError(f"unsupported record type: {record_type}")
