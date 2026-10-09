from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings

GATEWAY = "/internal/agent-tools"


def _phone(account_id: str) -> str:
    return "138" + str(int(UUID(account_id)) % 10**8).zfill(8)


def _agent(scope, call_id: str) -> dict[str, str]:
    account_id, family_id, pregnancy_id, _ = scope
    return {
        "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
        "Actor-Account-Id": account_id,
        "Family-Id": family_id,
        "Pregnancy-Id": pregnancy_id,
        "Eve-Session-Id": f"eve-batch-{account_id}",
        "Idempotency-Key": call_id,
    }


def _scope(client: TestClient):
    account_id = str(uuid4())
    token = issue_session_token(UUID(account_id), _phone(account_id), get_settings().auth_secret)
    public = {"Authorization": f"Bearer {token}"}
    family = client.post(
        "/api/v1/families", headers=public, json={"name": "批量家庭", "role": "mother"}
    ).json()
    pregnancy = client.post(
        f"/api/v1/families/{family['id']}/pregnancies",
        headers=public,
        json={"due_date": "2027-01-12"},
    ).json()
    client.post(
        f"/api/v1/pregnancies/{pregnancy['id']}/plan", headers=public, json={"as_of": "2026-08-14"}
    )
    return account_id, family["id"], pregnancy["id"], public


def _titles(client, scope) -> dict[str, dict]:
    plan = client.get(f"/api/v1/pregnancies/{scope[2]}/plan", headers=scope[3]).json()
    return {task["title"]: task for task in plan["tasks"]}


def _create(client, scope, titles: list[str], call_id: str) -> dict:
    response = client.post(
        f"{GATEWAY}/create-task",
        headers=_agent(scope, call_id),
        json={"tasks": [{"title": title} for title in titles]},
    )
    assert response.status_code == 200, response.text
    return response.json()


class TestBatchCreate:
    """批量操作一次调用做完：38 条待办不该是 38 次工具调用。"""

    def test_creates_every_task_in_one_call(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            result = _create(client, scope, ["买奶瓶", "买湿巾", "买包被"], "c1")
            assert [t["title"] for t in result["data"]["tasks"]] == ["买奶瓶", "买湿巾", "买包被"]
            assert {"买奶瓶", "买湿巾", "买包被"} <= set(_titles(client, scope))

    def test_undo_removes_the_whole_batch(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            created = _create(client, scope, ["批量甲", "批量乙"], "c2")
            response = client.post(
                f"{GATEWAY}/undo-operation",
                headers=_agent(scope, "u1"),
                json={"operation_id": created["operation_id"]},
            )
            assert response.status_code == 200, response.text
            assert not {"批量甲", "批量乙"} & set(_titles(client, scope))

    def test_single_task_form_still_works(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            response = client.post(
                f"{GATEWAY}/create-task", headers=_agent(scope, "c3"), json={"title": "单条"}
            )
            assert response.status_code == 200, response.text
            assert response.json()["data"]["task_id"]


class TestBatchComplete:
    def test_completes_several_and_reports_failures_per_item(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            created = _create(client, scope, ["做完甲", "做完乙"], "c4")["data"]["tasks"]
            response = client.post(
                f"{GATEWAY}/complete-task",
                headers=_agent(scope, "k1"),
                json={
                    "tasks": [
                        {"task_id": created[0]["task_id"], "expected_version": 1},
                        {"task_id": created[1]["task_id"], "expected_version": 1},
                        # 版本不对：这一项失败，不能拖累前两项。
                        {"task_id": created[1]["task_id"], "expected_version": 1},
                    ]
                },
            )
            assert response.status_code == 200, response.text
            data = response.json()["data"]
            assert [t["title"] for t in data["tasks"]] == ["做完甲", "做完乙"]
            assert len(data["failed"]) == 1
            titles = _titles(client, scope)
            assert titles["做完甲"]["status"] == "done"
            assert titles["做完乙"]["status"] == "done"

    def test_undo_restores_the_whole_batch(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            created = _create(client, scope, ["撤回甲", "撤回乙"], "c5")["data"]["tasks"]
            completed = client.post(
                f"{GATEWAY}/complete-task",
                headers=_agent(scope, "k2"),
                json={"tasks": [{"task_id": t["task_id"], "expected_version": 1} for t in created]},
            ).json()
            response = client.post(
                f"{GATEWAY}/undo-operation",
                headers=_agent(scope, "u2"),
                json={"operation_id": completed["operation_id"]},
            )
            assert response.status_code == 200, response.text
            titles = _titles(client, scope)
            assert titles["撤回甲"]["status"] != "done"
            assert titles["撤回乙"]["status"] != "done"


class TestBatchDelete:
    def test_deletes_several_behind_one_approval(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            created = _create(client, scope, ["删甲", "删乙", "留丙"], "c6")["data"]["tasks"]
            ids = [created[0]["task_id"], created[1]["task_id"]]

            gated = client.post(
                f"{GATEWAY}/delete-task", headers=_agent(scope, "x1"), json={"task_ids": ids}
            )
            assert gated.status_code == 409
            assert gated.json()["error"]["code"] == "approval_required"

            response = client.post(
                f"{GATEWAY}/delete-task",
                headers=_agent(scope, "x2"),
                json={"task_ids": ids, "approved": True},
            )
            assert response.status_code == 200, response.text
            assert [t["title"] for t in response.json()["data"]["tasks"]] == ["删甲", "删乙"]
            titles = _titles(client, scope)
            assert "留丙" in titles and not {"删甲", "删乙"} & set(titles)

    def test_a_foreign_task_in_the_batch_is_refused_before_anything_is_deleted(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            other = _scope(client)
            mine = _create(client, scope, ["我的"], "c7")["data"]["tasks"][0]["task_id"]
            theirs = _create(client, other, ["别人的"], "c8")["data"]["tasks"][0]["task_id"]

            response = client.post(
                f"{GATEWAY}/delete-task",
                headers=_agent(scope, "x3"),
                json={"task_ids": [mine, theirs], "approved": True},
            )
            assert response.status_code == 403, response.text
            assert "我的" in _titles(client, scope)
