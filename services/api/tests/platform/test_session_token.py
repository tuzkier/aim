from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import SESSION_TTL_SECONDS, issue_session_token
from aim_api.platform.config.settings import get_settings


def test_session_lasts_thirty_days() -> None:
    # 原来是 1 小时。免密时代无所谓，加了密码就变成每小时手输一次密码。
    assert SESSION_TTL_SECONDS == 30 * 24 * 3600


def test_issued_token_carries_that_expiry() -> None:
    token = issue_session_token(uuid4(), "13800000000", "secret", now=0)
    import base64
    import json

    payload = json.loads(base64.urlsafe_b64decode(token.split(".")[2] + "=="))
    assert payload["exp"] == SESSION_TTL_SECONDS


def test_demo_session_endpoint_is_gone() -> None:
    # 开放注册的前提下若保留免密通道，任何人仍可绕过密码进入，密码就只是装饰。
    with TestClient(create_app(settings=get_settings())) as client:
        response = client.post("/api/v1/auth/demo-session", json={"phone": "13800000000"})
        assert response.status_code == 404
