from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from aim_api.contexts.guidance.application.queries.get_encyclopedia import (
    EncyclopediaError,
    load_encyclopedia,
)


def _write(directory: Path, topic: str, entries: list[dict], *, status: str = "reviewed") -> None:
    document = {
        "id": f"encyclopedia-{topic}",
        "version": "1.0.0",
        "source": "测试来源",
        "source_url": "https://example.com",
        "reviewed_at": "2026-10-09" if status == "reviewed" else None,
        "review_status": status,
        "entries": entries,
    }
    (directory / f"{topic}.yaml").write_text(
        yaml.safe_dump(document, allow_unicode=True), encoding="utf-8"
    )


def _entry(entry_id: str, *, weeks: tuple[int, int] | None = None, **extra) -> dict:
    entry = {
        "id": entry_id,
        "title": f"标题{entry_id.split('.')[-1]}",
        "summary": "一句话摘要，说清楚这条讲什么",
        "sections": [{"heading": "是什么", "text": "这是一段足够长的正文内容。"}],
        "ask": ["这个要注意什么", "什么时候找医生"],
    }
    if weeks is not None:
        entry["weeks"] = list(weeks)
    entry.update(extra)
    return entry


def test_drafts_are_skipped_unless_included(tmp_path: Path) -> None:
    _write(tmp_path, "body", [_entry("body.nausea")], status="draft")
    _write(tmp_path, "diet", [_entry("diet.iron")])

    published = load_encyclopedia(tmp_path, include_drafts=False)
    everything = load_encyclopedia(tmp_path, include_drafts=True)

    assert [e.id for e in published.entries] == ["diet.iron"]
    assert [e.id for e in everything.entries] == ["body.nausea", "diet.iron"]


def test_entries_follow_topic_order_not_file_name_order(tmp_path: Path) -> None:
    _write(tmp_path, "paperwork", [_entry("paperwork.leave", kind="policy", link="https://example.com/a")])
    _write(tmp_path, "checkup", [_entry("checkup.nt")])

    encyclopedia = load_encyclopedia(tmp_path, include_drafts=True)

    assert [e.id for e in encyclopedia.entries] == ["checkup.nt", "paperwork.leave"]


def test_entry_id_must_carry_its_topic_prefix(tmp_path: Path) -> None:
    _write(tmp_path, "body", [_entry("diet.iron")])
    with pytest.raises(EncyclopediaError, match="body"):
        load_encyclopedia(tmp_path, include_drafts=True)


def test_duplicate_ids_are_rejected(tmp_path: Path) -> None:
    _write(tmp_path, "body", [_entry("body.cramp"), _entry("body.cramp")])
    with pytest.raises(EncyclopediaError, match="body.cramp"):
        load_encyclopedia(tmp_path, include_drafts=True)


def test_policy_entries_need_an_official_link(tmp_path: Path) -> None:
    _write(tmp_path, "paperwork", [_entry("paperwork.allowance", kind="policy")])
    with pytest.raises(EncyclopediaError, match="link"):
        load_encyclopedia(tmp_path, include_drafts=True)


def test_invalid_week_range_is_rejected(tmp_path: Path) -> None:
    _write(tmp_path, "body", [_entry("body.edema", weeks=(30, 20))])
    with pytest.raises(EncyclopediaError, match="weeks"):
        load_encyclopedia(tmp_path, include_drafts=True)


def test_unknown_topic_files_are_rejected(tmp_path: Path) -> None:
    _write(tmp_path, "gossip", [_entry("gossip.x")])
    with pytest.raises(EncyclopediaError, match="gossip"):
        load_encyclopedia(tmp_path, include_drafts=True)


def test_missing_directory_is_an_empty_encyclopedia(tmp_path: Path) -> None:
    assert load_encyclopedia(tmp_path / "nope", include_drafts=True).entries == ()


def test_catalog_for_a_week_ranks_the_closest_start_first(tmp_path: Path) -> None:
    _write(tmp_path, "body", [
        _entry("body.early", weeks=(4, 12)),
        _entry("body.mid", weeks=(20, 30)),
        _entry("body.always"),
        _entry("body.now", weeks=(24, 28)),
    ])
    encyclopedia = load_encyclopedia(tmp_path, include_drafts=True)

    entries = encyclopedia.catalog(week=25)["entries"]

    # 全程适用的条目也算覆盖本周，但排在有明确孕周的条目之后。
    assert [e["id"] for e in entries] == ["body.now", "body.mid", "body.always"]


def test_catalog_lists_topics_with_counts_and_filters_by_topic(tmp_path: Path) -> None:
    _write(tmp_path, "diet", [_entry("diet.iron"), _entry("diet.fish")])
    _write(tmp_path, "body", [_entry("body.cramp", weeks=(20, 36))])
    encyclopedia = load_encyclopedia(tmp_path, include_drafts=True)

    catalog = encyclopedia.catalog()
    by_topic = encyclopedia.catalog(topic="diet")

    assert catalog["topics"] == [
        {"id": "body", "name": "身体变化与不适", "count": 1},
        {"id": "diet", "name": "饮食营养", "count": 2},
    ]
    assert catalog["entries"][0] == {
        "id": "body.cramp", "topic": "body", "title": "标题cramp",
        "aliases": [], "weeks": [20, 36], "summary": "一句话摘要，说清楚这条讲什么",
    }
    assert [e["id"] for e in by_topic["entries"]] == ["diet.iron", "diet.fish"]


def test_detail_resolves_related_titles_and_drops_unpublished_links(tmp_path: Path) -> None:
    _write(
        tmp_path,
        "diet",
        [_entry("diet.iron", related=["diet.fish", "body.secret"]), _entry("diet.fish")],
    )
    _write(tmp_path, "body", [_entry("body.secret")], status="draft")
    encyclopedia = load_encyclopedia(tmp_path, include_drafts=False)

    detail = encyclopedia.detail("diet.iron")

    assert detail is not None
    assert detail["related"] == [{"id": "diet.fish", "title": "标题fish"}]
    assert detail["sections"] == [{"heading": "是什么", "text": "这是一段足够长的正文内容。"}]
    assert detail["ask"] == ["这个要注意什么", "什么时候找医生"]
    assert detail["review_status"] == "reviewed"
    assert detail["reviewed_at"] == "2026-10-09"
    assert encyclopedia.detail("diet.nope") is None
