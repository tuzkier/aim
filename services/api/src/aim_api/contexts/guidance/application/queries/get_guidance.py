from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml

from aim_api.contexts.guidance.domain.guidance_item import GuidanceItem

WORKSPACE_ROOT = Path(__file__).resolve().parents[8]


@dataclass(frozen=True, slots=True)
class GetGuidanceQuery:
    gestational_week: int
    region: str = "CN-ZJ-HZ"


def _load_week_document() -> dict:
    path = WORKSPACE_ROOT / "content/pregnancy-tasks/week-18.yaml"
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def execute(query: GetGuidanceQuery) -> tuple[GuidanceItem, ...]:
    document = _load_week_document()
    applicability = document["applicability"]
    if query.gestational_week not in applicability["gestational_weeks"]:
        return ()
    if query.region not in applicability["region"] and "CN" not in applicability["region"]:
        return ()
    items = [GuidanceItem.from_document(document, item) for item in document["items"]]
    return tuple(sorted(items, key=lambda item: (-item.priority, item.due_in_days, item.id)))


def initial_plan_items(gestational_week: int, region: str = "CN-ZJ-HZ") -> tuple[GuidanceItem, ...]:
    return execute(GetGuidanceQuery(gestational_week=gestational_week, region=region))
