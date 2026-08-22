from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Any

# 紧急程度排序：数值越小越靠前。未知等级排在最后，不会挤掉真正紧急的条目。
_SEVERITY_ORDER = {"urgent": 0, "same_day": 1, "routine": 2}


@dataclass(frozen=True, slots=True)
class SafetyRule:
    """孕期危险信号。

    与 GuidanceItem 的形状不同：这里是「出现什么情况 → 该做什么」，
    没有孕周与截止时间的概念。
    """

    id: str
    condition: str
    action: str
    severity: str
    source: str
    source_url: str
    reviewed_at: date

    @property
    def severity_rank(self) -> int:
        return _SEVERITY_ORDER.get(self.severity, len(_SEVERITY_ORDER))

    @classmethod
    def from_document(cls, document: dict[str, Any], item: dict[str, Any]) -> SafetyRule:
        return cls(
            id=str(item["id"]),
            condition=str(item["condition"]),
            action=str(item["action"]),
            severity=str(item.get("severity", "routine")),
            source=str(document["source"]),
            source_url=str(document["source_url"]),
            reviewed_at=date.fromisoformat(str(document["reviewed_at"])),
        )
