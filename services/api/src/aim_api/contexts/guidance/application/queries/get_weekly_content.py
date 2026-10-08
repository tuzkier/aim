"""孕周内容：第 4–42 周每周一条（水果比喻、身长体重、宝宝、妈妈、建议）。

整份下发（约 40 条），App 本地缓存，不按周单独请求。
"""

from __future__ import annotations

from typing import Any

import yaml

from aim_api.contexts.guidance.application.queries.get_guidance import CONTENT_ROOT

WEEKLY_DOCUMENT = "weekly/weeks.yaml"


def execute() -> dict[str, Any]:
    document = yaml.safe_load((CONTENT_ROOT / WEEKLY_DOCUMENT).read_text(encoding="utf-8"))
    return {
        "source": str(document["source"]),
        "source_url": str(document["source_url"]),
        "reviewed_at": str(document["reviewed_at"]),
        "weeks": sorted(
            (
                {
                    "week": int(week["week"]),
                    "fruit": str(week["fruit"]),
                    "fruit_name": str(week["fruit_name"]),
                    "length_cm": week["length_cm"],
                    "weight_g": week["weight_g"],
                    "baby": str(week["baby"]),
                    "mom": str(week["mom"]),
                    "tips": [str(tip) for tip in week["tips"]],
                }
                for week in document["weeks"]
            ),
            key=lambda week: week["week"],
        ),
    }
