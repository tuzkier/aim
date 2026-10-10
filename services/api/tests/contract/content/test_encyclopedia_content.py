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


def _section_text(entry_id: str, heading: str) -> str:
    for path in DOCUMENTS:
        for entry in yaml.safe_load(path.read_text(encoding="utf-8"))["entries"]:
            if entry["id"] == entry_id:
                return next(s["text"] for s in entry["sections"] if s["heading"] == heading)
    raise AssertionError(f"找不到 {entry_id}/{heading}")


#: 这些小节写的都是危险信号里的 urgent 情况（胎动减少、子痫前期、破水或出血、自伤念头），
#: 措辞要和危险信号一样说「立即」，不能写成「尽快」让人以为可以等一等。
URGENT_SECTIONS = [
    ("body.fetal-movement", "怎么数"),
    ("body.edema", "什么时候找医生"),
    ("body.heartburn", "什么时候找医生"),
    ("body.discharge", "什么时候找医生"),
    ("body.mood", "什么时候找医生"),
    ("body.frequent-urination", "什么时候找医生"),
    ("birth.signs-of-labor", "破水"),
    ("checkup.amniocentesis", "什么时候找医生"),
]


@pytest.mark.parametrize("entry_id,heading", URGENT_SECTIONS, ids=lambda v: str(v))
def test_urgent_signs_say_go_now_like_the_red_flags(entry_id: str, heading: str) -> None:
    text = _section_text(entry_id, heading)
    assert "立即" in text
    assert "尽快" not in text


#: 对应 same_day 危险信号（孕早期少量出血、剧吐、手脚心瘙痒）的小节写「今天」联系，
#: 与危险信号同档，不写含糊的「尽快」，也不升成「立即」吓人。
SAME_DAY_SECTIONS = [
    ("body.early-bleeding-pain", "什么时候找医生"),
    ("body.morning-sickness", "什么时候找医生"),
    ("diet.eating-with-nausea", "什么时候找医生"),
    ("body.stretch-marks", "什么时候找医生"),
]


@pytest.mark.parametrize("entry_id,heading", SAME_DAY_SECTIONS, ids=lambda v: str(v))
def test_same_day_signs_say_today_like_the_red_flags(entry_id: str, heading: str) -> None:
    text = _section_text(entry_id, heading)
    assert "今天" in text
    assert "尽快" not in text


def test_self_harm_thoughts_point_to_the_hotline_and_emergency() -> None:
    text = _section_text("body.mood", "什么时候找医生")
    assert "立即告诉身边的人" in text
    assert "12356" in text and "急诊" in text
