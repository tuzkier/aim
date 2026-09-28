from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings

GATEWAY = "/internal/agent-tools"


def _phone(account_id: str) -> str:
    return "138" + str(int(UUID(account_id)) % 10**8).zfill(8)


def _public_headers(account_id: str, phone: str) -> dict[str, str]:
    token = issue_session_token(UUID(account_id), phone, get_settings().auth_secret)
    return {"Authorization": f"Bearer {token}"}


def _agent_headers(
    account_id: str,
    family_id: str,
    pregnancy_id: str,
    *,
    call_id: str = "call-1",
) -> dict[str, str]:
    return {
        "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
        "Actor-Account-Id": account_id,
        "Family-Id": family_id,
        "Pregnancy-Id": pregnancy_id,
        "Eve-Session-Id": f"eve-authoring-{account_id}",
        "Idempotency-Key": call_id,
    }


def _scope(client: TestClient):
    account_id = str(uuid4())
    phone = _phone(account_id)
    public = _public_headers(account_id, phone)
    family = client.post(
        "/api/v1/families", headers=public, json={"name": "Agent 家庭", "role": "mother"}
    ).json()
    pregnancy = client.post(
        f"/api/v1/families/{family['id']}/pregnancies",
        headers=public,
        json={"due_date": "2027-01-12"},
    ).json()
    # create_task 需要孕期已有计划（Task 挂在 plan 下）。
    client.post(
        f"/api/v1/pregnancies/{pregnancy['id']}/plan",
        headers=public,
        json={"as_of": "2026-08-14"},
    )
    return account_id, phone, family["id"], pregnancy["id"], public


class TestCreateTaskTool:
    """Agent 建的待办要标成 agent 来源，时间线才会显示「Agent 调整」。"""

    def test_creates_a_task_attributed_to_the_agent(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)

            response = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id),
                json={"title": "预约产检", "description": "本周内完成"},
            )
            assert response.status_code == 200, response.text
            task_id = response.json()["data"]["task_id"]

            plan = client.get(
                f"/api/v1/pregnancies/{pregnancy_id}/plan", headers=public
            ).json()
            created = next(task for task in plan["tasks"] if task["id"] == task_id)
            assert created["title"] == "预约产检"
            assert created["changed_by_actor_type"] == "agent"

    def test_replaying_the_same_call_id_does_not_create_twice(self) -> None:
        """Eve 重试或流断线重连会重放同一 call_id，不能变成两条待办。"""
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)
            headers = _agent_headers(account_id, family_id, pregnancy_id, call_id="call-dup")
            body = {"title": "只应出现一次"}

            first = client.post(f"{GATEWAY}/create-task", headers=headers, json=body)
            second = client.post(f"{GATEWAY}/create-task", headers=headers, json=body)
            assert first.status_code == 200, first.text
            assert second.status_code == 200, second.text
            assert first.json()["data"]["task_id"] == second.json()["data"]["task_id"]

            plan = client.get(
                f"/api/v1/pregnancies/{pregnancy_id}/plan", headers=public
            ).json()
            matches = [t for t in plan["tasks"] if t["title"] == "只应出现一次"]
            assert len(matches) == 1


class TestCreateRecordTool:
    def test_creates_a_record_the_user_can_see(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)

            response = client.post(
                f"{GATEWAY}/create-record",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="r1"),
                json={"record_type": "note", "content": "记得带既往报告"},
            )
            assert response.status_code == 200, response.text
            record_id = response.json()["data"]["record_id"]

            records = client.get(
                f"/api/v1/pregnancies/{pregnancy_id}/records", headers=public
            ).json()
            assert any(record["id"] == record_id for record in records["records"])


class TestPermissionTiersStayDistinct:
    """完成待办挪到「直接执行」，改期仍要确认。"""

    def test_complete_task_executes_directly_and_returns_change_id(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)
            task_id = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t1"),
                json={"title": "产检"},
            ).json()["data"]["task_id"]

            response = client.post(
                f"{GATEWAY}/complete-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t2"),
                json={"task_id": task_id, "expected_version": 1},
            )
            assert response.status_code == 200, response.text
            data = response.json()["data"]
            assert data["status"] == "done"
            assert data["title"] == "产检"
            assert UUID(data["change_id"])

    def test_reschedule_task_still_requires_approval(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)
            task_id = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t3"),
                json={"title": "先建一条"},
            ).json()["data"]["task_id"]

            response = client.post(
                f"{GATEWAY}/reschedule-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t4"),
                json={
                    "task_id": task_id,
                    "expected_version": 1,
                    "kind": "delay",
                    "at": "2026-10-09T09:00:00Z",
                },
            )
            assert response.status_code == 409, response.text
            assert response.json()["error"]["code"] == "approval_required"

    def test_approved_reschedule_returns_change_id(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)
            task_id = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t5"),
                json={"title": "改期对象"},
            ).json()["data"]["task_id"]

            response = client.post(
                f"{GATEWAY}/reschedule-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t6"),
                json={
                    "task_id": task_id,
                    "expected_version": 1,
                    "kind": "schedule",
                    "at": "2026-10-09T09:00:00Z",
                    "approved": True,
                },
            )
            assert response.status_code == 200, response.text
            assert UUID(response.json()["data"]["change_id"])
            assert response.json()["data"]["status"] == "scheduled"

    def test_update_task_endpoint_is_gone(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)
            response = client.post(
                f"{GATEWAY}/update-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t7"),
                json={},
            )
            assert response.status_code == 404
