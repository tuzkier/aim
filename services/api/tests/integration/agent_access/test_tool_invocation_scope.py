from __future__ import annotations

import os
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings

GATEWAY = "/internal/agent-tools"


def _sync_url() -> str:
    return os.environ["DATABASE_URL"].replace("+asyncpg", "+psycopg", 1)


def _phone(account_id: str) -> str:
    return "138" + str(int(UUID(account_id)) % 10**8).zfill(8)


def test_invocation_remembers_who_it_acted_for() -> None:
    """撤销要校验「这次操作是不是你的」，调用记录里就得有账号与孕期。"""
    account_id = str(uuid4())
    phone = _phone(account_id)
    token = issue_session_token(UUID(account_id), phone, get_settings().auth_secret)
    public = {"Authorization": f"Bearer {token}"}
    with TestClient(create_app()) as client:
        family = client.post(
            "/api/v1/families", headers=public, json={"name": "作用域家庭", "role": "mother"}
        ).json()
        pregnancy = client.post(
            f"/api/v1/families/{family['id']}/pregnancies",
            headers=public,
            json={"due_date": "2027-01-12"},
        ).json()
        client.post(
            f"/api/v1/pregnancies/{pregnancy['id']}/plan",
            headers=public,
            json={"as_of": "2026-08-14"},
        )
        response = client.post(
            f"{GATEWAY}/create-task",
            headers={
                "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
                "Actor-Account-Id": account_id,
                "Family-Id": family["id"],
                "Pregnancy-Id": pregnancy["id"],
                "Eve-Session-Id": f"eve-scope-{account_id}",
                "Idempotency-Key": "scope-1",
            },
            json={"title": "记下作用域"},
        )
        assert response.status_code == 200, response.text
        operation_id = response.json()["operation_id"]

    engine = create_engine(_sync_url())
    with engine.connect() as conn:
        row = conn.execute(
            text(
                "SELECT account_id, family_id, pregnancy_id, undone_at "
                "FROM tool_invocations WHERE operation_id = :id"
            ),
            {"id": operation_id},
        ).one()
    engine.dispose()
    assert str(row.account_id) == account_id
    assert str(row.family_id) == family["id"]
    assert str(row.pregnancy_id) == pregnancy["id"]
    assert row.undone_at is None
