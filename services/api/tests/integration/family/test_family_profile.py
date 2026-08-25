from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings


def _phone() -> str:
    return "138" + str(int(uuid4()) % 10**8).zfill(8)


def _register(client: TestClient, role: str = "mother", nickname: str | None = None):
    body: dict[str, object] = {"phone": _phone(), "password": "a-good-password", "role": role}
    if nickname is not None:
        body["nickname"] = nickname
    return client.post("/api/v1/auth/register", json=body).json()


def _headers(session: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {session['token']}"}


def _get_family(client: TestClient, session: dict) -> dict:
    return client.get(f"/api/v1/families/{session['family_id']}", headers=_headers(session)).json()


def test_family_can_be_renamed() -> None:
    # 建家庭时名字写死成「我的家庭」，此前没有任何改名入口。
    with TestClient(create_app(settings=get_settings())) as client:
        session = _register(client)
        response = client.patch(
            f"/api/v1/families/{session['family_id']}",
            headers=_headers(session),
            json={"name": "王家"},
        )
        assert response.status_code == 200, response.text
        assert _get_family(client, session)["name"] == "王家"


def test_member_can_change_their_own_nickname_and_role() -> None:
    # 注册时选错角色此前没有任何补救路径。
    with TestClient(create_app(settings=get_settings())) as client:
        session = _register(client, role="mother")
        response = client.patch(
            f"/api/v1/families/{session['family_id']}/members/me",
            headers=_headers(session),
            json={"role": "father", "nickname": "爸爸"},
        )
        assert response.status_code == 200, response.text
        member = _get_family(client, session)["members"][0]
        assert member["role"] == "father"
        assert member["nickname"] == "爸爸"


def test_patching_only_the_nickname_leaves_the_role_alone() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        session = _register(client, role="other_caregiver", nickname="婆婆")
        client.patch(
            f"/api/v1/families/{session['family_id']}/members/me",
            headers=_headers(session),
            json={"nickname": "奶奶"},
        )
        member = _get_family(client, session)["members"][0]
        assert member["nickname"] == "奶奶"
        assert member["role"] == "other_caregiver"


def test_a_stranger_cannot_touch_someone_elses_family() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        owner = _register(client)
        stranger = _register(client)
        response = client.patch(
            f"/api/v1/families/{owner['family_id']}",
            headers=_headers(stranger),
            json={"name": "抢来的"},
        )
        assert response.status_code in (403, 404), response.text
        assert _get_family(client, owner)["name"] == "我的家庭"


def test_an_empty_family_name_is_rejected() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        session = _register(client)
        response = client.patch(
            f"/api/v1/families/{session['family_id']}",
            headers=_headers(session),
            json={"name": "   "},
        )
        assert response.status_code == 422, response.text
