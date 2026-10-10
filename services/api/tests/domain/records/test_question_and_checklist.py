from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from aim_api.contexts.records.domain.errors import RecordValidationError
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility

NOW = datetime(2026, 8, 22, 9, 0, tzinfo=UTC)


def make(record_type: RecordType, *, content=None, structured_data=None) -> Record:
    return Record.create(
        record_id=uuid4(),
        pregnancy_id=uuid4(),
        family_id=uuid4(),
        author_account_id=uuid4(),
        record_type=record_type,
        occurred_at=NOW,
        visibility=RecordVisibility.family,
        content=content,
        structured_data=structured_data or {},
        now=NOW,
    )


class TestQuestionRecords:
    """「想问医生」：平时冒出的疑问随手攒着，下次产检一次带走。
    做成记录类型而不是新建表，是为了直接复用增删查、可见性和 Agent 的 create_record。"""

    def test_a_question_is_just_its_text(self):
        record = make(RecordType.question, content="能不能继续游泳？")

        assert record.record_type is RecordType.question
        assert record.content == "能不能继续游泳？"

    def test_a_question_needs_text(self):
        with pytest.raises(RecordValidationError):
            make(RecordType.question, content="   ")

    def test_a_question_starts_unanswered(self):
        record = make(RecordType.question, content="能不能继续游泳？")

        assert record.structured_data.get("answered") is False

    def test_an_answered_question_carries_the_answer(self):
        record = make(
            RecordType.question,
            content="能不能继续游泳？",
            structured_data={"answered": True, "answer": "可以，注意水温"},
        )

        assert record.structured_data["answered"] is True
        assert record.structured_data["answer"] == "可以，注意水温"

    def test_answered_must_be_a_boolean(self):
        with pytest.raises(RecordValidationError):
            make(RecordType.question, content="问题", structured_data={"answered": "yes"})

    def test_a_question_can_point_back_at_its_report(self):
        """从产检报告里攒出来的问题记下它来自哪份报告，资料库据此把两者连起来。"""
        report_id = str(uuid4())
        record = make(
            RecordType.question,
            content="尿蛋白一个加号要紧吗？",
            structured_data={"answered": False, "report_id": report_id},
        )

        assert record.structured_data["report_id"] == report_id

    @pytest.mark.parametrize("report_id", ["not-a-uuid", "", 123, ["x"]])
    def test_report_id_must_be_a_uuid_string(self, report_id):
        with pytest.raises(RecordValidationError):
            make(
                RecordType.question,
                content="问题",
                structured_data={"report_id": report_id},
            )


class TestChecklistRecords:
    """办事指南与待产准备共用一套机制：内容库给出条目清单，
    用户的勾选状态存成 checklist 记录。两个分类因此都天然获得 Agent 写入能力。"""

    def test_a_checklist_entry_points_at_a_content_item(self):
        record = make(
            RecordType.checklist,
            structured_data={"collection": "preparation", "item_id": "id-card", "done": True},
        )

        assert record.structured_data["collection"] == "preparation"
        assert record.structured_data["item_id"] == "id-card"
        assert record.structured_data["done"] is True

    def test_a_checklist_entry_needs_a_collection_and_item(self):
        with pytest.raises(RecordValidationError):
            make(RecordType.checklist, structured_data={"done": True})

    def test_done_must_be_a_boolean(self):
        with pytest.raises(RecordValidationError):
            make(
                RecordType.checklist,
                structured_data={"collection": "preparation", "item_id": "x", "done": 1},
            )

    def test_done_defaults_to_false(self):
        record = make(
            RecordType.checklist,
            structured_data={"collection": "preparation", "item_id": "id-card"},
        )

        assert record.structured_data["done"] is False
