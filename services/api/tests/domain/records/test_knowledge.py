from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from aim_api.contexts.records.domain.errors import RecordValidationError
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility

NOW = datetime(2026, 8, 22, 9, 0, tzinfo=UTC)


def make(title="条目", **data):
    return Record.create(
        record_id=uuid4(), pregnancy_id=uuid4(), family_id=uuid4(),
        author_account_id=uuid4(), record_type=RecordType.knowledge,
        occurred_at=NOW, visibility=RecordVisibility.family,
        title=title, structured_data=data, now=NOW,
    )


class TestRecipe:
    """菜谱要能渲染成食材清单 + 编号步骤，所以两者都必须有。"""

    def test_a_recipe_keeps_ingredients_and_steps(self):
        record = make(
            category="nutrition", form="recipe",
            ingredients=["菠菜 200g", "猪肝 100g"],
            steps=["猪肝切片焯水", "下菠菜煮 3 分钟"],
        )

        assert record.structured_data["ingredients"] == ["菠菜 200g", "猪肝 100g"]
        assert len(record.structured_data["steps"]) == 2

    def test_a_recipe_without_ingredients_is_rejected(self):
        with pytest.raises(RecordValidationError):
            make(category="nutrition", form="recipe", steps=["随便煮煮"])

    def test_a_recipe_without_steps_is_rejected(self):
        with pytest.raises(RecordValidationError):
            make(category="nutrition", form="recipe", ingredients=["菠菜"])

    def test_empty_strings_do_not_count_as_content(self):
        with pytest.raises(RecordValidationError):
            make(category="nutrition", form="recipe", ingredients=["  "], steps=["煮"])


class TestFoodRule:
    """孕期饮食大量情况是「可以但要限量」。只给能/不能两档会逼出
    错误的绝对化结论，所以 verdict 是三档。"""

    def test_records_a_verdict_and_a_reason(self):
        record = make(
            category="nutrition", form="food_rule",
            verdict="limit", reason="咖啡因每日总量有上限，具体请咨询医生",
        )

        assert record.structured_data["verdict"] == "limit"

    def test_all_three_verdicts_are_accepted(self):
        for verdict in ("safe", "limit", "avoid"):
            make(category="nutrition", form="food_rule", verdict=verdict, reason="原因")

    def test_an_unknown_verdict_is_rejected(self):
        with pytest.raises(RecordValidationError):
            make(category="nutrition", form="food_rule", verdict="maybe", reason="原因")

    def test_a_verdict_without_a_reason_is_rejected(self):
        """只给结论不给原因，用户没法判断这条是否适用于自己。"""
        with pytest.raises(RecordValidationError):
            make(category="nutrition", form="food_rule", verdict="avoid")


class TestHowToAndTip:
    def test_a_howto_needs_steps(self):
        record = make(category="paperwork", form="howto", steps=["带身份证去社区服务中心"])

        assert record.structured_data["steps"]

    def test_a_howto_without_steps_is_rejected(self):
        with pytest.raises(RecordValidationError):
            make(category="paperwork", form="howto")

    def test_a_tip_is_just_a_body(self):
        record = make(category="preparation", form="tip", body="待产包提前一个月准备好")

        assert record.structured_data["body"]

    def test_a_tip_without_a_body_is_rejected(self):
        with pytest.raises(RecordValidationError):
            make(category="preparation", form="tip", body="   ")


class TestKnowledgeShape:
    def test_a_title_is_required(self):
        with pytest.raises(RecordValidationError):
            make(title="  ", category="nutrition", form="tip", body="正文")

    def test_an_unknown_form_is_rejected(self):
        with pytest.raises(RecordValidationError):
            make(category="nutrition", form="poem", body="正文")

    def test_an_unknown_category_is_rejected(self):
        """分类决定条目出现在哪张卡下。写错分类等于存进了一个看不见的地方。"""
        with pytest.raises(RecordValidationError):
            make(category="astrology", form="tip", body="正文")
