from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

from aim_api.contexts.agent_access.adapters.inbound.http import router as agent_router
from aim_api.contexts.guidance.domain.safety_rule import SafetyRule

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings


def _phone(account_id: str) -> str:
    return "138" + str(int(UUID(account_id)) % 10**8).zfill(8)


def test_context_lists_active_members_so_assign_can_work() -> None:
    account_id = str(uuid4())
    token = issue_session_token(UUID(account_id), _phone(account_id), get_settings().auth_secret)
    public = {"Authorization": f"Bearer {token}"}
    with TestClient(create_app()) as client:
        family = client.post(
            "/api/v1/families", headers=public, json={"name": "成员家庭", "role": "mother"}
        ).json()
        pregnancy = client.post(
            f"/api/v1/families/{family['id']}/pregnancies",
            headers=public,
            json={"due_date": "2027-01-12"},
        ).json()
        response = client.post(
            "/internal/agent-tools/get-pregnancy-context",
            headers={
                "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
                "Actor-Account-Id": account_id,
                "Family-Id": family["id"],
                "Pregnancy-Id": pregnancy["id"],
                "Eve-Session-Id": f"eve-context-{account_id}",
                "Idempotency-Key": "ctx-1",
            },
            json={},
        )
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    assert data["self_member_id"] == account_id
    assert data["members"] == [
        {"member_id": account_id, "display_name": "妈妈", "role": "mother"}
    ]


def test_context_includes_red_flags_for_current_week() -> None:
    account_id = str(uuid4())
    token = issue_session_token(UUID(account_id), _phone(account_id), get_settings().auth_secret)
    public = {"Authorization": f"Bearer {token}"}
    # 孕 8 周 3 天：预产期在末次月经后 280 天，今天距末次月经 59 天。
    # 孕周按 UTC 今天算，与接口一致。
    due_date = datetime.now(UTC).date() + timedelta(days=280 - 59)
    with TestClient(create_app()) as client:
        family = client.post(
            "/api/v1/families", headers=public, json={"name": "危险信号家庭", "role": "mother"}
        ).json()
        pregnancy = client.post(
            f"/api/v1/families/{family['id']}/pregnancies",
            headers=public,
            json={"due_date": due_date.isoformat()},
        ).json()
        response = client.post(
            "/internal/agent-tools/get-pregnancy-context",
            headers={
                "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
                "Actor-Account-Id": account_id,
                "Family-Id": family["id"],
                "Pregnancy-Id": pregnancy["id"],
                "Eve-Session-Id": f"eve-red-flags-{account_id}",
                "Idempotency-Key": "ctx-red-flags",
            },
            json={},
        )
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    assert data["gestational_age"]["weeks"] == 8
    red_flags = data["red_flags"]
    assert red_flags
    assert all(set(flag) == {"id", "condition", "action", "severity"} for flag in red_flags)
    severities = [flag["severity"] for flag in red_flags]
    assert set(severities) <= {"urgent", "same_day"}
    # urgent 全部排在 same_day 前面。
    assert severities == sorted(severities, key=lambda s: s != "urgent")
    assert "urgent" in severities and "same_day" in severities
    ids = {flag["id"] for flag in red_flags}
    assert "ectopic-signs" in ids
    # 孕 8 周还不到这些信号的孕周窗口，接口必须按孕周过滤掉。
    assert ids.isdisjoint(
        {"late-bleeding", "preterm-contractions", "waters-breaking", "reduced-fetal-movement"}
    )


def _rule(rule_id: str, severity: str, weeks: tuple[int, int] | None = None) -> SafetyRule:
    return SafetyRule(
        id=rule_id,
        condition=f"{rule_id} 的情况",
        action=f"{rule_id} 的处理",
        severity=severity,
        source="测试",
        source_url="https://example.com",
        reviewed_at=date(2026, 10, 1),
        weeks=weeks,
    )


@pytest.fixture
def fake_rules(monkeypatch: pytest.MonkeyPatch) -> list[int | None]:
    """把危险信号换成四条假数据，并记下 _red_flags 传进来的孕周。"""
    rules = (
        _rule("always-urgent", "urgent"),
        _rule("late-urgent", "urgent", weeks=(20, 42)),
        _rule("always-same-day", "same_day"),
        _rule("always-routine", "routine"),
    )
    received: list[int | None] = []

    def fake_get_safety_rules(week: int | None = None) -> tuple[SafetyRule, ...]:
        received.append(week)
        return tuple(rule for rule in rules if week is None or rule.applies(week))

    monkeypatch.setattr(agent_router, "get_safety_rules", fake_get_safety_rules)
    return received


def test_red_flags_drop_routine_and_rules_outside_the_week(fake_rules: list[int | None]) -> None:
    flags = agent_router._red_flags(8)
    assert fake_rules == [8]
    assert [flag["id"] for flag in flags] == ["always-urgent", "always-same-day"]
    assert flags[0] == {
        "id": "always-urgent",
        "condition": "always-urgent 的情况",
        "action": "always-urgent 的处理",
        "severity": "urgent",
    }


def test_red_flags_without_week_keep_every_urgent_and_same_day(
    fake_rules: list[int | None],
) -> None:
    flags = agent_router._red_flags(None)
    assert fake_rules == [None]
    assert [flag["id"] for flag in flags] == ["always-urgent", "late-urgent", "always-same-day"]


def test_red_flags_past_42_weeks_keep_the_late_pregnancy_signs() -> None:
    """用真实内容：孕 45 周（过了预产期很久）也要看到晚孕急症。"""
    ids = {flag["id"] for flag in agent_router._red_flags(45)}
    assert {"late-bleeding", "waters-breaking", "reduced-fetal-movement"} <= ids
