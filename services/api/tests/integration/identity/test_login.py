from __future__ import annotations

import time
from uuid import uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings

LOGIN_FAILURE = "手机号或密码不对"


def _phone() -> str:
    return "138" + str(int(uuid4()) % 10**8).zfill(8)


def _register(client: TestClient, phone: str, password: str = "a-good-password"):
    return client.post(
        "/api/v1/auth/register",
        json={"phone": phone, "password": password, "role": "mother"},
    )


def test_login_returns_a_token() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        phone = _phone()
        _register(client, phone)
        response = client.post(
            "/api/v1/auth/login", json={"phone": phone, "password": "a-good-password"}
        )
        assert response.status_code == 200, response.text
        assert response.json()["token"].startswith("aim.v1.")


def test_login_returns_the_existing_family_not_a_new_one() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        phone = _phone()
        registered = _register(client, phone).json()
        logged_in = client.post(
            "/api/v1/auth/login", json={"phone": phone, "password": "a-good-password"}
        ).json()
        assert logged_in["family_id"] == registered["family_id"]
        assert logged_in["account_id"] == registered["account_id"]


def test_wrong_password_and_unknown_phone_are_indistinguishable() -> None:
    # 区分开这两种情况，登录接口就成了手机号枚举器：
    # 攻击者能靠它探明哪些号已注册。
    with TestClient(create_app(settings=get_settings())) as client:
        phone = _phone()
        _register(client, phone)
        wrong = client.post("/api/v1/auth/login", json={"phone": phone, "password": "nope-nope"})
        unknown = client.post(
            "/api/v1/auth/login", json={"phone": _phone(), "password": "nope-nope"}
        )
        assert wrong.status_code == unknown.status_code == 401
        assert wrong.json() == unknown.json()
        assert LOGIN_FAILURE in wrong.text


def test_unknown_phone_is_not_faster_than_a_wrong_password() -> None:
    # 时序差异同样是枚举通道：不存在的号若立刻返回、存在的号要算一次哈希，
    # 响应时间就把答案说出来了。
    with TestClient(create_app(settings=get_settings())) as client:
        phone = _phone()
        _register(client, phone)

        def elapsed(body: dict[str, str]) -> float:
            start = time.perf_counter()
            client.post("/api/v1/auth/login", json=body)
            return time.perf_counter() - start

        wrong = min(elapsed({"phone": phone, "password": "nope-nope"}) for _ in range(3))
        unknown = min(elapsed({"phone": _phone(), "password": "nope-nope"}) for _ in range(3))
        assert unknown > wrong * 0.5, f"不存在的号快太多：{unknown:.4f}s vs {wrong:.4f}s"
