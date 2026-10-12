"""宫缩计时的摘要：最近一小时的次数、平均间隔、平均持续与 5-1-1 档位。

以最后一次宫缩的开始时刻为参考，数据定了结论就定了；iOS 计时页用同一套规则
（Features/Labor/ContractionModels.swift 的 ContractionMath），两边共用
contracts/fixtures/contraction-summary-vectors.json 的测试向量。
"""

from __future__ import annotations

import math
from typing import Any

HOUR_SECONDS = 3600
HALF_HOUR_SECONDS = 1800
# 「持续 1 小时」：第一次与最后一次开始之间最多差一个间隔，所以放宽到 55 分钟。
GO_MIN_SPAN_SECONDS = 3300
GO_MAX_INTERVAL_SECONDS = 300
# 手按「结束」普遍偏早，「每次约 1 分钟」按平均 50 秒判断。
GO_MIN_DURATION_SECONDS = 50
APPROACHING_MIN_COUNT = 4
APPROACHING_MAX_INTERVAL_SECONDS = 420


def _round(value: float) -> int:
    # 四舍五入到整秒；不用 round()，它是银行家舍入，和 iOS 的 .rounded() 不一致。
    return math.floor(value + 0.5)


def _average_interval(starts: list[int]) -> float | None:
    if len(starts) < 2:
        return None
    return (starts[-1] - starts[0]) / (len(starts) - 1)


def contraction_summary(contractions: list[dict[str, Any]]) -> dict[str, Any]:
    starts = [item["start"] for item in contractions]
    durations = [item["duration"] for item in contractions]
    latest = starts[-1]

    hour = [i for i, start in enumerate(starts) if start >= latest - HOUR_SECONDS]
    half = [i for i, start in enumerate(starts) if start >= latest - HALF_HOUR_SECONDS]
    hour_starts = [starts[i] for i in hour]
    hour_interval = _average_interval(hour_starts)
    hour_duration = sum(durations[i] for i in hour) / len(hour)
    half_interval = _average_interval([starts[i] for i in half])

    pattern = "early"
    if (
        hour_interval is not None
        and hour_interval <= GO_MAX_INTERVAL_SECONDS
        and hour_duration >= GO_MIN_DURATION_SECONDS
        and latest - hour_starts[0] >= GO_MIN_SPAN_SECONDS
    ):
        pattern = "go"
    elif (
        len(half) >= APPROACHING_MIN_COUNT
        and half_interval is not None
        and half_interval <= APPROACHING_MAX_INTERVAL_SECONDS
    ):
        pattern = "approaching"

    return {
        "count": len(contractions),
        "last_hour_count": len(hour),
        "avg_interval_seconds": None if hour_interval is None else _round(hour_interval),
        "avg_duration_seconds": _round(hour_duration),
        "pattern": pattern,
    }
