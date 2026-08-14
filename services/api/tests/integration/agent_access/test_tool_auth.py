from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings


def _phone(account_id: str, prefix: str = "138") -> str:
    return prefix + str(int(UUID(account_id)) % 10**8).zfill(8)


def _public_headers(account_id: str, phone: str) -> dict[str, str]:
    token = issue_session_token(UUID(account_id), phone, get_settings().auth_secret)
    return {"Authorization": f"Bearer {token}"}


def _agent_headers(
    account_id: str,
    family_id: str,
    pregnancy_id: str,
    *,
    session_id: str = "eve-session-test",
    call_id: str = "call-1",
    service_secret: str | None = None,
) -> dict[str, str]:
    session_id = f"{session_id}-{account_id}"
    return {
        "Service-Authorization": f"Bearer {service_secret or get_settings().agent_service_secret}",
        "Actor-Account-Id": account_id,
        "Family-Id": family_id,
        "Pregnancy-Id": pregnancy_id,
        "Eve-Session-Id": session_id,
        "Idempotency-Key": call_id,
    }


def _scope(client: TestClient) -> tuple[str, str, str, str, dict[str, str]]:
    account_id = str(uuid4())
    phone = _phone(account_id)
    public = _public_headers(account_id, phone)
    family = client.post(
        "/api/v1/families", headers=public, json={"name": "Agent 家庭", "role": "mother"}
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
    return account_id, family["id"], pregnancy["id"], phone, public


def test_internal_tool_rechecks_scope_and_ignores_model_ids() -> None:
    with TestClient(create_app()) as client:
        account_id, family_id, pregnancy_id, _, _ = _scope(client)
        response = client.post(
            "/internal/agent-tools/get-pregnancy-context",
            headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="context-1"),
            json={"family_id": str(uuid4()), "pregnancy_id": str(uuid4())},
        )
        assert response.status_code == 200, response.text
        assert response.json()["data"]["family_id"] == family_id
        assert response.json()["data"]["pregnancy_id"] == pregnancy_id

        unauthenticated = client.post(
            "/internal/agent-tools/get-pregnancy-context",
            headers=_agent_headers(
                account_id, family_id, pregnancy_id, call_id="context-2", service_secret="wrong"
            ),
            json={},
        )
        assert unauthenticated.status_code == 401


def test_service_credential_cannot_replace_family_membership() -> None:
    with TestClient(create_app()) as client:
        account_id, family_id, pregnancy_id, _, _ = _scope(client)
        stranger_id = str(uuid4())
        forbidden = client.post(
            "/internal/agent-tools/get-pregnancy-context",
            headers=_agent_headers(stranger_id, family_id, pregnancy_id, call_id="context-3"),
            json={},
        )
        assert forbidden.status_code == 403
