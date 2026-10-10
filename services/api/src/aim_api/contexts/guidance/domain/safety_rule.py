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
    没有截止时间。多数信号整个孕期都适用（weeks 为 None），
    少数只在特定孕周有意义，例如宫外孕只看孕早期。
    """

    id: str
    condition: str
    action: str
    severity: str
    source: str
    source_url: str
    reviewed_at: date
    weeks: tuple[int, int] | None = None

    def applies(self, week: int) -> bool:
        """该孕周是否适用；weeks 两端都包含在内。"""
        if self.weeks is None:
            return True
        return self.weeks[0] <= week <= self.weeks[1]

    @property
    def severity_rank(self) -> int:
        return _SEVERITY_ORDER.get(self.severity, len(_SEVERITY_ORDER))

    @classmethod
    def from_document(cls, document: dict[str, Any], item: dict[str, Any]) -> SafetyRule:
        weeks = item.get("weeks")
        return cls(
            id=str(item["id"]),
            condition=str(item["condition"]),
            action=str(item["action"]),
            severity=str(item.get("severity", "routine")),
            source=str(document["source"]),
            source_url=str(document["source_url"]),
            reviewed_at=date.fromisoformat(str(document["reviewed_at"])),
            weeks=(int(weeks[0]), int(weeks[1])) if weeks else None,
        )
