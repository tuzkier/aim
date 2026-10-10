from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[5]


def _validate(schema_path: Path, document_path: Path) -> None:
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    document = yaml.safe_load(document_path.read_text(encoding="utf-8"))
    errors = sorted(
        Draft202012Validator(schema).iter_errors(document), key=lambda error: error.path
    )
    assert errors == [], "\n".join(error.message for error in errors)


@pytest.mark.parametrize(
    "document_path",
    sorted((Path(__file__).resolve().parents[5] / "content/pregnancy-tasks").glob("*.yaml")),
)
def test_pregnancy_task_content_has_version_and_applicability(document_path: Path) -> None:
    root = Path(__file__).resolve().parents[5]
    _validate(
        root / "content/pregnancy-tasks/schema.json",
        document_path,
    )


def test_safety_and_hangzhou_content_have_source_and_review_date() -> None:
    _validate(
        ROOT / "content/safety-rules/schema.json",
        ROOT / "content/safety-rules/pregnancy-red-flags.yaml",
    )
    _validate(
        ROOT / "content/hangzhou/schema.json",
        ROOT / "content/hangzhou/pregnancy-benefits.yaml",
    )


def test_safety_rule_week_ranges_are_ordered() -> None:
    """schema 只管得了 weeks 是两个 4–42 的整数，管不了起止颠倒。"""
    document = yaml.safe_load(
        (ROOT / "content/safety-rules/pregnancy-red-flags.yaml").read_text(encoding="utf-8")
    )
    reversed_ranges = [
        item["id"]
        for item in document["items"]
        if "weeks" in item and item["weeks"][0] > item["weeks"][1]
    ]
    assert reversed_ranges == []


def test_weekly_content_matches_its_schema() -> None:
    _validate(ROOT / "content/weekly/schema.json", ROOT / "content/weekly/weeks.yaml")


BROWSABLE_DOCUMENTS = sorted(
    path
    for collection in ("nutrition", "preparation")
    for path in (ROOT / "content" / collection).glob("*.yaml")
)


def test_browsable_collections_are_not_empty() -> None:
    assert {path.parent.name for path in BROWSABLE_DOCUMENTS} == {"nutrition", "preparation"}


@pytest.mark.parametrize(
    "document_path", BROWSABLE_DOCUMENTS, ids=lambda p: f"{p.parent.name}/{p.name}"
)
def test_browsable_collections_match_their_schema(document_path: Path) -> None:
    """资料库直接展示的内容集合同样要过 schema——生产里「吃什么」还在回退读 nutrition。"""
    _validate(document_path.parent / "schema.json", document_path)


def _task_documents() -> list[dict]:
    return [
        yaml.safe_load(path.read_text(encoding="utf-8"))
        for path in sorted((ROOT / "content/pregnancy-tasks").glob("*.yaml"))
    ]


def test_pregnancy_task_ids_are_globally_unique() -> None:
    ids = [item["id"] for document in _task_documents() for item in document["items"]]
    assert len(ids) == len(set(ids)), sorted({i for i in ids if ids.count(i) > 1})


def test_every_week_from_4_to_42_has_task_templates() -> None:
    covered = {
        week
        for document in _task_documents()
        for week in document["applicability"]["gestational_weeks"]
    }
    assert [week for week in range(4, 43) if week not in covered] == []


def test_task_titles_and_summaries_stay_short() -> None:
    too_long = [
        item["id"]
        for document in _task_documents()
        for item in document["items"]
        if len(item["title"]) > 20 or len(item["summary"]) > 60
    ]
    assert too_long == []


def test_initial_plan_items_is_not_empty_for_weeks_4_to_42() -> None:
    from aim_api.contexts.guidance.application.queries.get_guidance import initial_plan_items

    assert [week for week in range(4, 43) if not initial_plan_items(week)] == []


def test_fetal_movement_tasks_say_go_now_like_the_red_flag() -> None:
    """胎动不足 10 次或明显减少是 urgent 危险信号；待办文本生成后就固定在任务里，必须写「立即」。"""
    items = [
        item
        for document in _task_documents()
        for item in document["items"]
        if "不足 10 次" in item["summary"]
    ]
    assert items, "应当有提醒数胎动的待办"
    for item in items:
        assert "立即联系医院或去产科急诊" in item["summary"], item["id"]
        assert "尽快" not in item["summary"], item["id"]


def test_no_first_movement_by_24_weeks_does_not_wait_for_the_next_visit() -> None:
    by_id = {item["id"]: item for document in _task_documents() for item in document["items"]}
    summary = by_id["w20-first-movement"]["summary"]
    assert "尽快联系产检医院" in summary
    assert "产检时告诉医生" not in summary
