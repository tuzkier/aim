from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings


def _phone() -> str:
    return "138" + str(int(uuid4()) % 10**8).zfill(8)


def _register(client: TestClient) -> dict:
    return client.post(
        "/api/v1/auth/register",
        json={"phone": _phone(), "password": "a-good-password", "role": "mother"},
    ).json()


def _headers(session: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {session['token']}"}


def _create(client: TestClient, session: dict, *, eve_id: str, title: str):
    return client.post(
        "/api/v1/agent/sessions",
        headers=_headers(session),
        json={"eve_session_id": eve_id, "title": title},
    )


def test_a_session_can_be_recorded_and_listed() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        account = _register(client)
        created = _create(client, account, eve_id="wrun_a", title="孕期能喝咖啡吗")
        assert created.status_code == 201, created.text

        listed = client.get("/api/v1/agent/sessions", headers=_headers(account)).json()
        assert [item["title"] for item in listed["sessions"]] == ["孕期能喝咖啡吗"]
        assert listed["sessions"][0]["eve_session_id"] == "wrun_a"


def test_sessions_come_back_most_recently_active_first() -> None:
    # 打开 AIM 默认接着最近那段，排序错了就会接到旧的那段上。
    with TestClient(create_app(settings=get_settings())) as client:
        account = _register(client)
        first = _create(client, account, eve_id="wrun_1", title="第一段").json()
        _create(client, account, eve_id="wrun_2", title="第二段")

        # 回到第一段继续聊，它就该重新排到最前面。
        client.patch(
            f"/api/v1/agent/sessions/{first['id']}",
            headers=_headers(account),
            json={"touch": True},
        )

        listed = client.get("/api/v1/agent/sessions", headers=_headers(account)).json()
        assert [item["title"] for item in listed["sessions"]] == ["第一段", "第二段"]


def test_another_account_cannot_see_your_conversations() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        mine = _register(client)
        _create(client, mine, eve_id="wrun_private", title="很私人的问题")

        stranger = _register(client)
        listed = client.get("/api/v1/agent/sessions", headers=_headers(stranger)).json()
        assert listed["sessions"] == []


def test_touching_someone_elses_session_looks_like_it_does_not_exist() -> None:
    # 返回 403 等于确认「这个 id 存在」，会话 id 就成了可探测的。
    with TestClient(create_app(settings=get_settings())) as client:
        mine = _register(client)
        created = _create(client, mine, eve_id="wrun_x", title="我的").json()

        stranger = _register(client)
        response = client.patch(
            f"/api/v1/agent/sessions/{created['id']}",
            headers=_headers(stranger),
            json={"title": "抢来的"},
        )
        assert response.status_code == 404, response.text


def test_a_session_can_be_renamed() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        account = _register(client)
        created = _create(client, account, eve_id="wrun_r", title="原标题").json()
        client.patch(
            f"/api/v1/agent/sessions/{created['id']}",
            headers=_headers(account),
            json={"title": "改过的标题"},
        )
        listed = client.get("/api/v1/agent/sessions", headers=_headers(account)).json()
        assert listed["sessions"][0]["title"] == "改过的标题"


def test_a_session_can_be_removed_from_the_list() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        account = _register(client)
        created = _create(client, account, eve_id="wrun_d", title="要删的").json()
        assert client.delete(
            f"/api/v1/agent/sessions/{created['id']}", headers=_headers(account)
        ).status_code == 204
        listed = client.get("/api/v1/agent/sessions", headers=_headers(account)).json()
        assert listed["sessions"] == []


def test_recording_the_same_eve_session_twice_is_not_an_error() -> None:
    # 客户端重试或并发都可能重复登记，重复不该让用户看到失败。
    with TestClient(create_app(settings=get_settings())) as client:
        account = _register(client)
        _create(client, account, eve_id="wrun_same", title="第一次")
        again = _create(client, account, eve_id="wrun_same", title="第二次")
        assert again.status_code in (200, 201), again.text

        listed = client.get("/api/v1/agent/sessions", headers=_headers(account)).json()
        assert len(listed["sessions"]) == 1
