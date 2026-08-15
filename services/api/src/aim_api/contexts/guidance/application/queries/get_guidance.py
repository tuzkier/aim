from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

import yaml

from aim_api.contexts.guidance.domain.guidance_item import GuidanceItem


def _default_content_root() -> Path:
    """Find the repository content directory without assuming a fixed install depth."""

    for parent in Path(__file__).resolve().parents:
        candidate = parent / "content"
        if (candidate / "pregnancy-tasks").is_dir():
            return candidate
    return Path(__file__).resolve().parent


CONTENT_ROOT = Path(os.environ.get("AIM_CONTENT_ROOT", _default_content_root()))


@dataclass(frozen=True, slots=True)
class GetGuidanceQuery:
    gestational_week: int
    region: str = "CN-ZJ-HZ"


def _load_week_documents() -> tuple[dict, ...]:
    content_dir = CONTENT_ROOT / "pregnancy-tasks"
    paths = sorted(content_dir.glob("*.yaml"))
    return tuple(yaml.safe_load(path.read_text(encoding="utf-8")) for path in paths)


def execute(query: GetGuidanceQuery) -> tuple[GuidanceItem, ...]:
    items: list[GuidanceItem] = []
    for document in _load_week_documents():
        applicability = document["applicability"]
        if query.gestational_week not in applicability["gestational_weeks"]:
            continue
        if query.region not in applicability["region"] and "CN" not in applicability["region"]:
            continue
        items.extend(GuidanceItem.from_document(document, item) for item in document["items"])
    return tuple(sorted(items, key=lambda item: (-item.priority, item.due_in_days, item.id)))


def initial_plan_items(gestational_week: int, region: str = "CN-ZJ-HZ") -> tuple[GuidanceItem, ...]:
    return execute(GetGuidanceQuery(gestational_week=gestational_week, region=region))
