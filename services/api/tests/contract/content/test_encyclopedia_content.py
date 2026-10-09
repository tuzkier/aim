from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml
from jsonschema import Draft202012Validator

from aim_api.contexts.guidance.application.queries.get_encyclopedia import load_encyclopedia
from aim_api.contexts.guidance.domain.encyclopedia import TOPICS

ROOT = Path(__file__).resolve().parents[5]
DIRECTORY = ROOT / "content/encyclopedia"
DOCUMENTS = sorted(DIRECTORY.glob("*.yaml"))


@pytest.mark.parametrize("document_path", DOCUMENTS, ids=lambda p: p.name)
def test_encyclopedia_document_matches_schema(document_path: Path) -> None:
    schema = json.loads((DIRECTORY / "schema.json").read_text(encoding="utf-8"))
    document = yaml.safe_load(document_path.read_text(encoding="utf-8"))
    errors = sorted(Draft202012Validator(schema).iter_errors(document), key=lambda e: list(e.path))
    assert errors == [], "\n".join(f"{list(e.path)}: {e.message}" for e in errors)


def test_every_topic_has_a_document() -> None:
    assert {path.stem for path in DOCUMENTS} == {topic for topic, _ in TOPICS}


def test_related_links_point_to_existing_entries() -> None:
    raw_ids: set[str] = set()
    raw_related: list[tuple[str, str]] = []
    for path in DOCUMENTS:
        for entry in yaml.safe_load(path.read_text(encoding="utf-8"))["entries"]:
            raw_ids.add(entry["id"])
            raw_related.extend((entry["id"], rid) for rid in entry.get("related", []))
    dangling = [(source, target) for source, target in raw_related if target not in raw_ids]
    assert dangling == []


def test_all_content_loads_together() -> None:
    encyclopedia = load_encyclopedia(DIRECTORY, include_drafts=True)
    assert len(encyclopedia.entries) >= 55


def test_every_week_has_at_least_two_entries() -> None:
    """只检查已审核的内容：草稿阶段的覆盖率不代表上线后的样子。"""
    published = load_encyclopedia(DIRECTORY, include_drafts=False)
    if not published.entries:
        pytest.skip("还没有审核通过的百科文件")
    thin = [
        week for week in range(4, 41)
        if sum(1 for e in published.entries if e.weeks and e.covers(week)) < 2
    ]
    assert thin == []


def test_drafts_cover_every_week_too() -> None:
    """草稿也要满足覆盖要求——否则审核通过的那天才发现缺口。"""
    everything = load_encyclopedia(DIRECTORY, include_drafts=True)
    thin = [
        week for week in range(4, 41)
        if sum(1 for e in everything.entries if e.weeks and e.covers(week)) < 2
    ]
    assert thin == []


def test_nutrition_basics_moved_into_diet() -> None:
    old = yaml.safe_load((ROOT / "content/nutrition/dietary-basics.yaml").read_text(encoding="utf-8"))
    encyclopedia = load_encyclopedia(DIRECTORY, include_drafts=True)
    for item in old["items"]:
        entry = encyclopedia.get(f"diet.{item['id']}")
        assert entry is not None, item["id"]
        assert entry.title == item["title"]
