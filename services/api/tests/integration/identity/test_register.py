from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings


def _phone() -> str:
    return "138" + str(int(uuid4()) % 10**8).zfill(8)


def _register(client: TestClient, **overrides: object):
    body: dict[str, object] = {
        "phone": _phone(),
        "password": "a-good-password",
        "role": "mother",
    }
    body.update(overrides)
    return client.post("/api/v1/auth/register", json=body)


def test_register_creates_account_family_and_token() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        response = _register(client)
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["token"].startswith("aim.v1.")
        assert body["family_id"]
        assert body["role"] == "mother"


def test_register_rejects_a_duplicate_phone() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        phone = _phone()
        assert _register(client, phone=phone).status_code == 201
        assert _register(client, phone=phone).status_code == 409


def test_register_rejects_a_short_password() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        assert _register(client, password="short").status_code == 422


def test_register_accepts_every_role() -> None:
    # 角色以前写死成 mother，爸爸和其他家人根本没有注册入口。
    with TestClient(create_app(settings=get_settings())) as client:
        for role in ("mother", "father", "other_caregiver"):
            response = _register(client, role=role)
            assert response.status_code == 201, response.text
            assert response.json()["role"] == role


def test_register_stores_the_nickname() -> None:
    # 成员只有角色没有名字时，两个「其他家人」在列表里分不出谁是谁。
    with TestClient(create_app(settings=get_settings())) as client:
        body = _register(client, role="other_caregiver", nickname="婆婆").json()
        family = client.get(
            f"/api/v1/families/{body['family_id']}",
            headers={"Authorization": f"Bearer {body['token']}"},
        ).json()
        assert family["members"][0]["nickname"] == "婆婆"


def test_the_password_is_never_echoed_back() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        response = _register(client, password="a-good-password")
        assert "a-good-password" not in response.text
        assert "password" not in response.json()
