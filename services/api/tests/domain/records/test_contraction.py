from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest

from aim_api.contexts.records.domain.contraction import contraction_summary
from aim_api.contexts.records.domain.errors import RecordValidationError
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility

NOW = datetime(2026, 10, 12, 3, 0, tzinfo=UTC)
VECTORS = json.loads(
    (Path(__file__).resolve().parents[5] / "contracts/fixtures/contraction-summary-vectors.json").read_text(
        encoding="utf-8"
    )
)["vectors"]


def entries(pairs: list[list[int]]) -> list[dict]:
    return [{"start": start, "duration": duration} for start, duration in pairs]


def make(structured_data: dict) -> Record:
    return Record.create(
        record_id=uuid4(),
        pregnancy_id=uuid4(),
        family_id=uuid4(),
        author_account_id=uuid4(),
        record_type=RecordType.contraction,
        occurred_at=NOW,
        visibility=RecordVisibility.family,
        title="宫缩计时 · 3 次",
        content=None,
        structured_data=structured_data,
        now=NOW,
    )


@pytest.mark.parametrize("vector", VECTORS, ids=[v["name"] for v in VECTORS])
def test_summary_matches_shared_vectors(vector):
    assert contraction_summary(entries(vector["contractions"])) == vector["expected"]


class TestContractionRecord:
    def test_server_computes_and_overrides_the_summary(self):
        record = make({
            "contractions": entries([[0, 60], [300, 60]]),
            "summary": {"pattern": "go", "count": 99},
        })
        assert record.structured_data["summary"] == {
            "count": 2,
            "last_hour_count": 2,
            "avg_interval_seconds": 300,
            "avg_duration_seconds": 60,
            "pattern": "early",
        }

    @pytest.mark.parametrize(
        "contractions",
        [
            [],
            entries([[5, 60]]),  # 首项必须为 0
            entries([[0, 60], [30, 60]]),  # 重叠
            entries([[0, 60], [300, 60], [200, 60]]),  # 递减
            entries([[0, 0]]),  # 持续不足 1 秒
            entries([[0, 601]]),  # 持续超过 10 分钟
            entries([[0, 60], [86401, 60]]),  # 超过 24 小时
            [{"start": 0}],  # 缺 duration
            [{"start": 0, "duration": True}],  # 布尔不算整数
            [[0, 60]],  # 必须是对象
        ],
    )
    def test_invalid_contractions_are_rejected(self, contractions):
        with pytest.raises(RecordValidationError):
            make({"contractions": contractions})

    def test_at_most_500_contractions(self):
        many = entries([[i * 120, 60] for i in range(501)])
        with pytest.raises(RecordValidationError):
            make({"contractions": many})
        make({"contractions": many[:500]})

    def test_back_to_back_contractions_are_allowed(self):
        make({"contractions": entries([[0, 60], [60, 60]])})

    def test_unknown_fields_are_rejected(self):
        with pytest.raises(RecordValidationError):
            make({"contractions": entries([[0, 60]]), "extra": 1})
