from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text

from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings

LOGIN_FAILURE = "手机号或密码不对"
PASSWORD = "a-good-password"


def _phone() -> str:
    return "138" + str(int(uuid4()) % 10**8).zfill(8)


def _register(client: TestClient, phone: str) -> dict:
    response = client.post(
        "/api/v1/auth/register", json={"phone": phone, "password": PASSWORD, "role": "mother"}
    )
    assert response.status_code == 201, response.text
    return response.json()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _backdate_deletion(account_id: str, days: int) -> None:
    """把申请时间往前拨，模拟缓冲期流逝。测试库地址来自 conftest 设好的 DATABASE_URL。"""
    url = get_settings().database_url.replace("+asyncpg", "+psycopg", 1)
    engine = create_engine(url)
    with engine.begin() as conn:
        conn.execute(
            text("UPDATE accounts SET deletion_requested_at = :at WHERE id = :id"),
            {"at": datetime.now(UTC) - timedelta(days=days), "id": UUID(account_id)},
        )
    engine.dispose()


def test_deletion_request_needs_the_password() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        session = _register(client, _phone())
        response = client.post(
            "/api/v1/auth/deletion-request",
            json={"password": "wrong-password"},
            headers=_auth(session["token"]),
        )
        assert response.status_code == 401
        assert LOGIN_FAILURE in response.text


def test_deletion_request_invalidates_existing_tokens() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        session = _register(client, _phone())
        headers = _auth(session["token"])
        family_url = f"/api/v1/families/{session['family_id']}"
        assert client.get(family_url, headers=headers).status_code == 200

        response = client.post(
            "/api/v1/auth/deletion-request", json={"password": PASSWORD}, headers=headers
        )
        assert response.status_code == 204, response.text

        assert client.get(family_url, headers=headers).status_code == 401
        # 幂等：再申请一次仍是 204，而不是因为票已失效而 401。
        again = client.post(
            "/api/v1/auth/deletion-request", json={"password": PASSWORD}, headers=headers
        )
        assert again.status_code == 204, again.text


def test_login_within_grace_period_cancels_deletion() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        phone = _phone()
        session = _register(client, phone)
        client.post(
            "/api/v1/auth/deletion-request",
            json={"password": PASSWORD},
            headers=_auth(session["token"]),
        )

        login = client.post("/api/v1/auth/login", json={"phone": phone, "password": PASSWORD})
        assert login.status_code == 200, login.text
        assert login.json()["deletion_cancelled"] is True

        # 恢复之后一切如常，再登录一次不再提示。
        again = client.post("/api/v1/auth/login", json={"phone": phone, "password": PASSWORD})
        assert again.json()["deletion_cancelled"] is False
        headers = _auth(again.json()["token"])
        family_url = f"/api/v1/families/{session['family_id']}"
        assert client.get(family_url, headers=headers).status_code == 200


def test_login_after_grace_period_looks_like_unknown_account() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        phone = _phone()
        session = _register(client, phone)
        client.post(
            "/api/v1/auth/deletion-request",
            json={"password": PASSWORD},
            headers=_auth(session["token"]),
        )
        _backdate_deletion(session["account_id"], days=31)

        login = client.post("/api/v1/auth/login", json={"phone": phone, "password": PASSWORD})
        unknown = client.post("/api/v1/auth/login", json={"phone": _phone(), "password": PASSWORD})
        assert login.status_code == unknown.status_code == 401
        assert login.json() == unknown.json()


def test_register_response_reports_no_cancellation() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        assert _register(client, _phone())["deletion_cancelled"] is False
