from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings


def _token(account_id: str, phone: str) -> str:
    return issue_session_token(UUID(account_id), phone, get_settings().auth_secret)


def _headers(account_id: str, phone: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {_token(account_id, phone)}"}


def test_family_is_only_readable_by_active_members() -> None:
    creator_id = str(uuid4())
    stranger_id = str(uuid4())
    creator_phone = "138" + str(int(UUID(creator_id)) % 10**8).zfill(8)
    stranger_phone = "139" + str(int(UUID(stranger_id)) % 10**8).zfill(8)

    with TestClient(create_app()) as client:
        created = client.post(
            "/api/v1/families",
            headers=_headers(creator_id, creator_phone),
            json={"name": "杭州的家", "role": "mother"},
        )
        assert created.status_code == 201, created.text
        family_id = created.json()["id"]

        assert (
            client.get(
                f"/api/v1/families/{family_id}", headers=_headers(creator_id, creator_phone)
            ).status_code
            == 200
        )
        forbidden = client.get(
            f"/api/v1/families/{family_id}", headers=_headers(stranger_id, stranger_phone)
        )
        assert forbidden.status_code == 403


def test_invitation_acceptance_is_one_time_and_activates_member() -> None:
    creator_id = str(uuid4())
    invitee_id = str(uuid4())
    creator_phone = "138" + str(int(UUID(creator_id)) % 10**8).zfill(8)
    invitee_phone = "139" + str(int(UUID(invitee_id)) % 10**8).zfill(8)

    with TestClient(create_app()) as client:
        created = client.post(
            "/api/v1/families",
            headers=_headers(creator_id, creator_phone),
            json={"name": "杭州的家", "role": "mother"},
        )
        family_id = created.json()["id"]

        invited = client.post(
            f"/api/v1/families/{family_id}/invitations",
            headers=_headers(creator_id, creator_phone),
            json={"invitee_phone": invitee_phone, "role": "father"},
        )
        assert invited.status_code == 201, invited.text
        token = invited.json()["token"]

        accepted = client.post(
            f"/api/v1/family-invitations/{token}/accept",
            headers=_headers(invitee_id, invitee_phone),
        )
        assert accepted.status_code == 200, accepted.text
        assert any(
            member["account_id"] == invitee_id and member["status"] == "active"
            for member in accepted.json()["members"]
        )

        replay = client.post(
            f"/api/v1/family-invitations/{token}/accept",
            headers=_headers(invitee_id, invitee_phone),
        )
        assert replay.status_code == 409
