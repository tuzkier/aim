from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from aim_api.contexts.records.domain.errors import RecordValidationError
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility

NOW = datetime(2026, 8, 22, 9, 0, tzinfo=UTC)
BASE = {
    "hospital": "市一医院",
    "exam_items": "常规产检",
    "result": "正常",
    "doctor_advice": "按时复查",
}


def make(**metrics):
    data = dict(BASE)
    if metrics:
        data["metrics"] = metrics
    return Record.create(
        record_id=uuid4(),
        pregnancy_id=uuid4(),
        family_id=uuid4(),
        author_account_id=uuid4(),
        record_type=RecordType.checkup,
        occurred_at=NOW,
        visibility=RecordVisibility.family,
        structured_data=data,
        now=NOW,
    )


class TestCheckupMetrics:
    """产检要能画趋势，就必须有可计算的数值，而不只是四段文字。
    指标是可选的——不是每次产检都测所有项。"""

    def test_metrics_are_optional(self):
        record = make()

        assert record.structured_data.get("metrics", {}) == {}

    def test_records_weight_and_blood_pressure(self):
        record = make(weight_kg=62.5, systolic=118, diastolic=75)

        metrics = record.structured_data["metrics"]
        assert metrics["weight_kg"] == 62.5
        assert metrics["systolic"] == 118

    def test_rejects_a_non_numeric_metric(self):
        with pytest.raises(RecordValidationError):
            make(weight_kg="六十二公斤")

    def test_rejects_an_unknown_metric(self):
        """未知指标名要挡住——否则错别字会静默变成一条永远没人看的数据。"""
        with pytest.raises(RecordValidationError):
            make(wieght_kg=62.5)

    def test_rejects_an_implausible_weight(self):
        """体重 500kg 几乎一定是输入错误。挡住明显不可能的值，
        但范围要足够宽——不替医生判断什么算异常。"""
        with pytest.raises(RecordValidationError):
            make(weight_kg=500)

    def test_accepts_the_full_plausible_range(self):
        make(weight_kg=38)
        make(weight_kg=200)
        make(systolic=70, diastolic=40)
        make(systolic=220, diastolic=140)

    def test_rejects_diastolic_above_systolic(self):
        """舒张压高于收缩压是不可能的，必然是填反了。"""
        with pytest.raises(RecordValidationError):
            make(systolic=80, diastolic=120)


def make_report(**data):
    return Record.create(
        record_id=uuid4(),
        pregnancy_id=uuid4(),
        family_id=uuid4(),
        author_account_id=uuid4(),
        record_type=RecordType.checkup,
        occurred_at=NOW,
        visibility=RecordVisibility.family,
        structured_data=data,
        now=NOW,
    )


def item(**overrides):
    return {"name": "尿蛋白", "value": "阴性", **overrides}


class TestCheckupReport:
    """产检报告：四段文字都可缺省，指标与其他化验项按需填写。"""

    def test_only_fetal_heart_rate_is_enough(self):
        record = make_report(metrics={"fetal_heart_rate": 145})

        assert record.structured_data["metrics"] == {"fetal_heart_rate": 145}

    def test_accepts_fundal_height_in_range(self):
        make_report(metrics={"fundal_height_cm": 10})
        make_report(metrics={"fundal_height_cm": 45})

    def test_rejects_implausible_fundal_height(self):
        with pytest.raises(RecordValidationError):
            make_report(metrics={"fundal_height_cm": 9})

    def test_rejects_implausible_fetal_heart_rate(self):
        with pytest.raises(RecordValidationError):
            make_report(metrics={"fetal_heart_rate": 99})
        with pytest.raises(RecordValidationError):
            make_report(metrics={"fetal_heart_rate": 201})

    def test_text_sections_may_be_omitted(self):
        make_report()

    def test_text_sections_may_be_null(self):
        make_report(hospital=None, exam_items=None, result=None, doctor_advice=None)

    @pytest.mark.parametrize("field", ["hospital", "exam_items", "result", "doctor_advice"])
    def test_rejects_non_string_text_section(self, field):
        with pytest.raises(RecordValidationError):
            make_report(**{field: 123})

    def test_keeps_the_existing_empty_string_payload(self):
        """agent 侧建产检记录时会给四段文字补空串，要继续兼容。"""
        make_report(hospital="", exam_items="", result="", doctor_advice="")

    def test_accepts_other_items(self):
        items = [
            item(),
            item(name="白细胞", value="12.1", unit="10^9/L", reference="3.5-9.5", flag="high"),
            item(name="血小板", value="90", unit=None, reference=None, flag="low"),
            item(name="乙肝表面抗原", value="阳性", flag="abnormal"),
            item(name="尿糖", value="阴性", flag=None),
        ]
        record = make_report(other_items=items)

        assert record.structured_data["other_items"] == items

    def test_accepts_up_to_sixty_other_items(self):
        make_report(other_items=[item(name=f"项{i}") for i in range(60)])

    def test_rejects_more_than_sixty_other_items(self):
        with pytest.raises(RecordValidationError):
            make_report(other_items=[item(name=f"项{i}") for i in range(61)])

    def test_rejects_other_items_that_is_not_a_list(self):
        with pytest.raises(RecordValidationError):
            make_report(other_items={"name": "尿蛋白", "value": "阴性"})

    def test_rejects_an_item_that_is_not_an_object(self):
        with pytest.raises(RecordValidationError):
            make_report(other_items=["尿蛋白 阴性"])

    def test_rejects_an_item_without_name(self):
        with pytest.raises(RecordValidationError):
            make_report(other_items=[{"value": "阴性"}])

    @pytest.mark.parametrize("name", ["", "   ", None, 1, "名" * 41])
    def test_rejects_an_invalid_item_name(self, name):
        with pytest.raises(RecordValidationError):
            make_report(other_items=[item(name=name)])

    @pytest.mark.parametrize("value", [12.1, None, "", "  ", "值" * 41])
    def test_rejects_an_invalid_item_value(self, value):
        with pytest.raises(RecordValidationError):
            make_report(other_items=[item(value=value)])

    def test_accepts_boundary_lengths(self):
        make_report(
            other_items=[
                item(name="名" * 40, value="值" * 40, unit="u" * 20, reference="r" * 60)
            ]
        )

    @pytest.mark.parametrize(
        "overrides",
        [{"unit": "u" * 21}, {"unit": 5}, {"reference": "r" * 61}, {"reference": 5}],
    )
    def test_rejects_invalid_unit_or_reference(self, overrides):
        with pytest.raises(RecordValidationError):
            make_report(other_items=[item(**overrides)])

    @pytest.mark.parametrize("flag", ["weird", ["high"], 1])
    def test_rejects_an_unknown_flag(self, flag):
        with pytest.raises(RecordValidationError):
            make_report(other_items=[item(flag=flag)])

    def test_rejects_unknown_item_keys(self):
        with pytest.raises(RecordValidationError):
            make_report(other_items=[item(note="复查")])
