from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

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
