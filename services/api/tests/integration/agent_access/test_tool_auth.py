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


def test_list_records_returns_only_records_visible_to_scoped_account() -> None:
    author_id, member_id = str(uuid4()), str(uuid4())
    author_phone, member_phone = _phone(author_id), _phone(member_id, "139")
    author_headers = _public_headers(author_id, author_phone)
    member_headers = _public_headers(member_id, member_phone)

    with TestClient(create_app()) as client:
        family = client.post(
            "/api/v1/families",
            headers=author_headers,
            json={"name": "记录权限家庭", "role": "mother"},
        ).json()
        pregnancy = client.post(
            f"/api/v1/families/{family['id']}/pregnancies",
            headers=author_headers,
            json={"due_date": "2027-01-12"},
        ).json()
        invitation = client.post(
            f"/api/v1/families/{family['id']}/invitations",
            headers=author_headers,
            json={"invitee_phone": member_phone, "role": "father"},
        ).json()
        accepted = client.post(
            f"/api/v1/family-invitations/{invitation['token']}/accept", headers=member_headers
        )
        assert accepted.status_code == 200, accepted.text

        family_record = client.post(
            f"/api/v1/pregnancies/{pregnancy['id']}/records",
            headers=author_headers,
            json={
                "type": "note",
                "occurred_at": "2026-08-16T09:00:00+08:00",
                "visibility": "family",
                "content": "全家可见",
                "structured_data": {},
            },
        )
        private_record = client.post(
            f"/api/v1/pregnancies/{pregnancy['id']}/records",
            headers=author_headers,
            json={
                "type": "symptom",
                "occurred_at": "2026-08-16T10:00:00+08:00",
                "visibility": "private",
                "structured_data": {"symptoms": ["nausea"], "severity": 3},
            },
        )
        response = client.post(
            "/internal/agent-tools/list-records",
            headers=_agent_headers(member_id, family["id"], pregnancy["id"], call_id="records-1"),
            json={"type": "note"},
        )

    assert family_record.status_code == 201, family_record.text
    assert private_record.status_code == 201, private_record.text
    assert response.status_code == 200, response.text
    assert response.json()["data"]["count"] == 1
    assert response.json()["data"]["records"] == [
        {
            "id": family_record.json()["id"],
            "type": "note",
            "occurred_at": "2026-08-16T01:00:00+00:00",
            "visibility": "family",
            "title": None,
            "content": "全家可见",
            "structured_data": {},
            "attachment_refs": [],
        }
    ]
