from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.contexts.guidance.adapters.inbound.http import router as guidance_router
from aim_api.contexts.guidance.domain.encyclopedia import (
    Encyclopedia,
    EncyclopediaEntry,
    EntrySection,
)


def _entry(
    entry_id: str, weeks: tuple[int, int] | None, related: tuple[str, ...] = ()
) -> EncyclopediaEntry:
    return EncyclopediaEntry(
        id=entry_id, topic=entry_id.split(".")[0], title=f"标题{entry_id}", aliases=("别名",),
        weeks=weeks, summary="摘要", sections=(EntrySection("是什么", "正文"),),
        ask=("问题一", "问题二"), related=related, kind=None, link=None,
        source="来源", source_url="https://example.com", reviewed_at="2026-10-09",
        review_status="reviewed",
    )


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch):
    fixture = Encyclopedia(entries=(
        _entry("body.cramp", (20, 36), related=("diet.iron",)),
        _entry("diet.iron", None),
    ))
    # 接口与真实内容文件解耦：内容还是草稿、或正在改写时，接口测试照样稳定。
    monkeypatch.setattr(guidance_router, "get_encyclopedia", lambda: fixture)
    with TestClient(create_app()) as test_client:
        yield test_client


def test_catalog_lists_topics_and_entries(client: TestClient) -> None:
    response = client.get("/api/v1/library/encyclopedia")

    assert response.status_code == 200, response.text
    body = response.json()
    assert [t["id"] for t in body["topics"]] == ["body", "diet"]
    assert [e["id"] for e in body["entries"]] == ["body.cramp", "diet.iron"]
    assert "sections" not in body["entries"][0]


def test_catalog_filters_by_week_and_topic(client: TestClient) -> None:
    by_week = client.get("/api/v1/library/encyclopedia", params={"week": 10}).json()
    by_topic = client.get("/api/v1/library/encyclopedia", params={"topic": "body"}).json()

    assert [e["id"] for e in by_week["entries"]] == ["diet.iron"]
    assert [e["id"] for e in by_topic["entries"]] == ["body.cramp"]


def test_entry_detail_and_missing_entry(client: TestClient) -> None:
    found = client.get("/api/v1/library/encyclopedia/body.cramp")
    missing = client.get("/api/v1/library/encyclopedia/body.nope")

    assert found.status_code == 200, found.text
    assert found.json()["related"] == [{"id": "diet.iron", "title": "标题diet.iron"}]
    assert missing.status_code == 404
