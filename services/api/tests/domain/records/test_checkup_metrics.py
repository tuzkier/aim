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
