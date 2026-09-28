from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings

GATEWAY = "/internal/agent-tools"


def _phone(account_id: str) -> str:
    return "138" + str(int(UUID(account_id)) % 10**8).zfill(8)


def _agent(account_id: str, family_id: str, pregnancy_id: str, call_id: str) -> dict[str, str]:
    return {
        "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
        "Actor-Account-Id": account_id,
        "Family-Id": family_id,
        "Pregnancy-Id": pregnancy_id,
        "Eve-Session-Id": f"eve-undo-{account_id}",
        "Idempotency-Key": call_id,
    }


def _scope(client: TestClient):
    account_id = str(uuid4())
    token = issue_session_token(UUID(account_id), _phone(account_id), get_settings().auth_secret)
    public = {"Authorization": f"Bearer {token}"}
    family = client.post(
        "/api/v1/families", headers=public, json={"name": "撤销家庭", "role": "mother"}
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
    return account_id, family["id"], pregnancy["id"], public


def _tasks(client: TestClient, pregnancy_id: str, public: dict[str, str]) -> dict[str, dict]:
    plan = client.get(f"/api/v1/pregnancies/{pregnancy_id}/plan", headers=public).json()
    return {task["id"]: task for task in plan["tasks"]}


def _undo_tool(client, scope, operation_id: str, call_id: str):
    account_id, family_id, pregnancy_id, _ = scope
    return client.post(
        f"{GATEWAY}/undo-operation",
        headers=_agent(account_id, family_id, pregnancy_id, call_id),
        json={"operation_id": operation_id},
    )


class TestUndoByOperationId:
    def test_undo_create_task_removes_it(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            account_id, family_id, pregnancy_id, public = scope
            created = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent(account_id, family_id, pregnancy_id, "c1"),
                json={"title": "待撤销"},
            ).json()

            response = _undo_tool(client, scope, created["operation_id"], "u1")
            assert response.status_code == 200, response.text
            assert created["data"]["task_id"] not in _tasks(client, pregnancy_id, public)

    def test_undo_complete_restores_status(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            account_id, family_id, pregnancy_id, public = scope
            task_id = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent(account_id, family_id, pregnancy_id, "c2"),
                json={"title": "产检"},
            ).json()["data"]["task_id"]
            completed = client.post(
                f"{GATEWAY}/complete-task",
                headers=_agent(account_id, family_id, pregnancy_id, "c3"),
                json={"task_id": task_id, "expected_version": 1},
            ).json()

            response = _undo_tool(client, scope, completed["operation_id"], "u2")
            assert response.status_code == 200, response.text
            assert _tasks(client, pregnancy_id, public)[task_id]["status"] != "done"

    def test_undo_create_record_hides_it(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            account_id, family_id, pregnancy_id, public = scope
            created = client.post(
                f"{GATEWAY}/create-record",
                headers=_agent(account_id, family_id, pregnancy_id, "c4"),
                json={"record_type": "note", "content": "待撤销"},
            ).json()

            response = _undo_tool(client, scope, created["operation_id"], "u3")
            assert response.status_code == 200, response.text
            records = client.get(
                f"/api/v1/pregnancies/{pregnancy_id}/records", headers=public
            ).json()["records"]
            assert all(record["id"] != created["data"]["record_id"] for record in records)

    def test_undo_twice_is_idempotent(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            account_id, family_id, pregnancy_id, public = scope
            created = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent(account_id, family_id, pregnancy_id, "c5"),
                json={"title": "撤两次"},
            ).json()

            first = _undo_tool(client, scope, created["operation_id"], "u4")
            second = _undo_tool(client, scope, created["operation_id"], "u5")
            assert first.status_code == 200, first.text
            assert second.status_code == 200, second.text
            assert second.json()["data"]["already_undone"] is True

    def test_undo_after_a_later_change_conflicts(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            account_id, family_id, pregnancy_id, public = scope
            task_id = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent(account_id, family_id, pregnancy_id, "c6"),
                json={"title": "后来又改过"},
            ).json()["data"]["task_id"]
            completed = client.post(
                f"{GATEWAY}/complete-task",
                headers=_agent(account_id, family_id, pregnancy_id, "c7"),
                json={"task_id": task_id, "expected_version": 1},
            ).json()
            # 之后用户自己又把它恢复成未完成：原来那次完成已经不是当前变更了。
            restored = client.post(
                f"/api/v1/task-changes/{completed['data']['change_id']}/undo",
                headers=public,
                json={"expected_version": 2},
            )
            assert restored.status_code == 200, restored.text

            response = _undo_tool(client, scope, completed["operation_id"], "u6")
            assert response.status_code == 409, response.text
            assert "之后又被改过" in response.json()["error"]["message"]

    def test_pregnancy_fact_cannot_be_undone(self) -> None:
        with TestClient(create_app()) as client:
            scope = _scope(client)
            account_id, family_id, pregnancy_id, public = scope
            recorded = client.post(
                f"{GATEWAY}/record-pregnancy-fact",
                headers=_agent(account_id, family_id, pregnancy_id, "c8"),
                json={
                    "key": "blood_type",
                    "value": "A",
                    "source": "user_confirmed",
                    "approved": True,
                },
            ).json()

            response = _undo_tool(client, scope, recorded["operation_id"], "u7")
            assert response.status_code == 409, response.text
            assert "孕期信息不能撤销" in response.json()["error"]["message"]


class TestPublicUndoEndpoint:
    def test_owner_can_undo_from_the_card(self) -> None:
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)
            created = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent(account_id, family_id, pregnancy_id, "p1"),
                json={"title": "卡片上撤销"},
            ).json()

            response = client.post(
                f"/api/v1/agent/operations/{created['operation_id']}/undo", headers=public
            )
            assert response.status_code == 200, response.text
            assert response.json()["already_undone"] is False
            assert created["data"]["task_id"] not in _tasks(client, pregnancy_id, public)

    def test_someone_else_cannot_undo(self) -> None:
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)
            _, _, _, other_public = _scope(client)
            created = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent(account_id, family_id, pregnancy_id, "p2"),
                json={"title": "别人的操作"},
            ).json()

            response = client.post(
                f"/api/v1/agent/operations/{created['operation_id']}/undo", headers=other_public
            )
            assert response.status_code == 403, response.text

    def test_unknown_operation_is_404(self) -> None:
        with TestClient(create_app()) as client:
            _, _, _, public = _scope(client)
            response = client.post(f"/api/v1/agent/operations/{uuid4()}/undo", headers=public)
            assert response.status_code == 404, response.text
