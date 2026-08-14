from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Any


@dataclass(frozen=True, slots=True)
class GuidanceItem:
    id: str
    version: str
    source: str
    source_url: str
    reviewed_at: date
    applicability: dict[str, Any]
    title: str
    summary: str
    due_in_days: int
    source_type: str = "template"
    priority: int = 0

    @classmethod
    def from_document(
        cls,
        document: dict[str, Any],
        item: dict[str, Any],
    ) -> GuidanceItem:
        return cls(
            id=str(item["id"]),
            version=str(document["version"]),
            source=str(document["source"]),
            source_url=str(document["source_url"]),
            reviewed_at=date.fromisoformat(str(document["reviewed_at"])),
            applicability=dict(document["applicability"]),
            title=str(item["title"]),
            summary=str(item["summary"]),
            due_in_days=int(item["due_in_days"]),
            source_type=str(item.get("source_type", "template")),
            priority=int(item.get("priority", 0)),
        )
