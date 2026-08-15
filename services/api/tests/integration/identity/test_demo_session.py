from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings


def test_demo_session_creates_and_reuses_a_human_facing_account() -> None:
    phone = "138" + str(int(uuid4()) % 10**8).zfill(8)
    settings = get_settings().model_copy(update={"dev_auth_enabled": True})

    with TestClient(create_app(settings=settings)) as client:
        first = client.post(
            "/api/v1/auth/demo-session",
            json={"phone": phone, "due_date": "2027-01-16"},
        )
        assert first.status_code == 201, first.text
        first_body = first.json()
        assert first_body["phone"] == phone
        assert first_body["role"] == "mother"
        assert first_body["token"].startswith("aim.v1.")

        second = client.post(
            "/api/v1/auth/demo-session",
            json={"phone": phone, "due_date": "2027-01-16"},
        )
        assert second.status_code == 200, second.text
        second_body = second.json()
        assert second_body["account_id"] == first_body["account_id"]
        assert second_body["family_id"] == first_body["family_id"]
        assert second_body["pregnancy_id"] == first_body["pregnancy_id"]

        family = client.get(
            f"/api/v1/families/{first_body['family_id']}",
            headers={"Authorization": f"Bearer {first_body['token']}"},
        )
        assert family.status_code == 200, family.text


def test_demo_session_is_not_available_when_disabled() -> None:
    settings = get_settings().model_copy(update={"dev_auth_enabled": False})

    with TestClient(create_app(settings=settings)) as client:
        response = client.post(
            "/api/v1/auth/demo-session",
            json={"phone": "13800000001", "due_date": "2027-01-16"},
        )

    assert response.status_code == 404


def test_demo_session_can_enter_without_a_due_date() -> None:
    phone = "139" + str(int(uuid4()) % 10**8).zfill(8)
    settings = get_settings().model_copy(update={"dev_auth_enabled": True})

    with TestClient(create_app(settings=settings)) as client:
        response = client.post(
            "/api/v1/auth/demo-session",
            json={"phone": phone},
        )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["phone"] == phone
    assert body["pregnancy_id"] is None
