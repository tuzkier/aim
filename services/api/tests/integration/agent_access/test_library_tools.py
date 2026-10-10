from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.contexts.guidance.application.queries.get_encyclopedia import get_encyclopedia
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings


def _phone(account_id: str) -> str:
    return "138" + str(int(UUID(account_id)) % 10**8).zfill(8)


def _scope(client: TestClient, account_id: str, *, weeks: int, days: int) -> dict[str, str]:
    """建一个家庭和孕期，返回调用内部工具要带的服务头（不含 Idempotency-Key）。"""
    token = issue_session_token(UUID(account_id), _phone(account_id), get_settings().auth_secret)
    public = {"Authorization": f"Bearer {token}"}
    # 预产期在末次月经后 280 天；孕周按 UTC 今天算，与接口一致。
    due_date = datetime.now(UTC).date() + timedelta(days=280 - (weeks * 7 + days))
    family = client.post(
        "/api/v1/families", headers=public, json={"name": "资料库家庭", "role": "mother"}
    ).json()
    pregnancy = client.post(
        f"/api/v1/families/{family['id']}/pregnancies",
        headers=public,
        json={"due_date": due_date.isoformat()},
    ).json()
    return {
        "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
        "Actor-Account-Id": account_id,
        "Family-Id": family["id"],
        "Pregnancy-Id": pregnancy["id"],
        "Eve-Session-Id": f"eve-library-{account_id}",
    }


def test_list_library_defaults_to_the_current_week() -> None:
    account_id = str(uuid4())
    with TestClient(create_app()) as client:
        headers = _scope(client, account_id, weeks=25, days=3)
        response = client.post(
            "/internal/agent-tools/list-library",
            headers={**headers, "Idempotency-Key": "library-1"},
            json={},
        )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "completed"
    data = body["data"]
    assert data["topics"]
    entries = data["entries"]
    assert entries
    # 目录只给摘要，不给正文。
    assert all("sections" not in entry for entry in entries)
    # pick 只给首页推荐用，Agent 用不上，不占它的上下文（公开接口仍带）。
    assert all("pick" not in entry for entry in entries)
    assert all(
        {"id", "topic", "title", "aliases", "weeks", "summary"} <= set(entry) for entry in entries
    )
    # 没传 week 时按当前孕周（25 周）过滤。
    assert all(
        entry["weeks"] is None or entry["weeks"][0] <= 25 <= entry["weeks"][1]
        for entry in entries
    )
    # 按 week_rank 排：有孕周范围的在前、起点越接近 25 越靠前，全程适用的排最后。
    ranks = [
        (1, 0) if entry["weeks"] is None else (0, abs(25 - entry["weeks"][0]))
        for entry in entries
    ]
    assert ranks == sorted(ranks)
    assert entries[0]["weeks"] is not None
    assert abs(25 - entries[0]["weeks"][0]) == min(
        abs(25 - entry["weeks"][0]) for entry in entries if entry["weeks"] is not None
    )


def test_list_library_filters_by_topic() -> None:
    account_id = str(uuid4())
    with TestClient(create_app()) as client:
        headers = _scope(client, account_id, weeks=25, days=3)
        response = client.post(
            "/internal/agent-tools/list-library",
            headers={**headers, "Idempotency-Key": "library-topic"},
            json={"topic": "diet"},
        )
    assert response.status_code == 200, response.text
    entries = response.json()["data"]["entries"]
    assert entries
    assert {entry["topic"] for entry in entries} == {"diet"}


def test_get_library_entry_returns_the_full_text_or_not_found() -> None:
    account_id = str(uuid4())
    with TestClient(create_app()) as client:
        headers = _scope(client, account_id, weeks=25, days=3)
        found = client.post(
            "/internal/agent-tools/get-library-entry",
            headers={**headers, "Idempotency-Key": "library-entry"},
            json={"id": "body.fetal-movement"},
        )
        missing = client.post(
            "/internal/agent-tools/get-library-entry",
            headers={**headers, "Idempotency-Key": "library-missing"},
            json={"id": "body.nope"},
        )
    assert found.status_code == 200, found.text
    data = found.json()["data"]
    assert data["id"] == "body.fetal-movement"
    assert data["title"] == "胎动与数胎动"
    assert data["sections"]
    assert all(section["heading"] and section["text"] for section in data["sections"])

    # 没有这条时不报错，让模型能如实说「没有这条」。
    assert missing.status_code == 200, missing.text
    assert missing.json()["status"] == "completed"
    assert missing.json()["data"] == {"found": False, "id": "body.nope"}


def test_list_library_by_topic_returns_the_whole_topic_not_only_this_week() -> None:
    """孕 12 周问分娩：birth 的条目都不在 12 周，带 topic 时也要看得到。"""
    account_id = str(uuid4())
    with TestClient(create_app()) as client:
        headers = _scope(client, account_id, weeks=12, days=0)
        response = client.post(
            "/internal/agent-tools/list-library",
            headers={**headers, "Idempotency-Key": "library-birth"},
            json={"topic": "birth"},
        )
    assert response.status_code == 200, response.text
    entries = response.json()["data"]["entries"]
    assert entries
    assert {entry["topic"] for entry in entries} == {"birth"}
    # 整个主题都在：条数等于目录里该主题的总数。
    topics = {topic["id"]: topic["count"] for topic in response.json()["data"]["topics"]}
    assert len(entries) == topics["birth"]
    # 仍按当前孕周排序：有孕周范围的在前、起点越接近 12 越靠前。
    ranks = [
        (1, 0) if entry["weeks"] is None else (0, abs(12 - entry["weeks"][0]))
        for entry in entries
    ]
    assert ranks == sorted(ranks)


def test_list_library_with_an_explicit_week_filters_by_that_week() -> None:
    account_id = str(uuid4())
    with TestClient(create_app()) as client:
        headers = _scope(client, account_id, weeks=25, days=3)
        response = client.post(
            "/internal/agent-tools/list-library",
            headers={**headers, "Idempotency-Key": "library-week-36"},
            json={"week": 36},
        )
    assert response.status_code == 200, response.text
    entries = response.json()["data"]["entries"]
    assert entries
    assert all(
        entry["weeks"] is None or entry["weeks"][0] <= 36 <= entry["weeks"][1]
        for entry in entries
    )
    # 确实换成了 36 周：至少有一条明确覆盖 36 周、但不覆盖当前 25 周的条目。
    assert any(
        entry["weeks"] is not None and not entry["weeks"][0] <= 25 <= entry["weeks"][1]
        for entry in entries
    )


def test_list_library_clamps_an_early_pregnancy_to_week_4() -> None:
    """孕 2 周时百科没有任何条目从 2 周开始，按 4 周过滤，目录不至于只剩全程条目。"""
    account_id = str(uuid4())
    with TestClient(create_app()) as client:
        headers = _scope(client, account_id, weeks=2, days=0)
        response = client.post(
            "/internal/agent-tools/list-library",
            headers={**headers, "Idempotency-Key": "library-clamp"},
            json={},
        )
    assert response.status_code == 200, response.text
    entries = response.json()["data"]["entries"]
    expected = get_encyclopedia().catalog(week=4)["entries"]
    assert [entry["id"] for entry in entries] == [entry["id"] for entry in expected]
    assert any(entry["weeks"] is not None and entry["weeks"][0] == 4 for entry in entries)
