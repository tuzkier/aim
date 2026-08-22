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


class TestDeleteTaskTool:
    """撤销「Agent 新建待办」走删除——undo_operation 是字段级还原，撤销不了新建。"""

    def test_deletes_a_task_the_agent_created(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)
            created = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="c1"),
                json={"title": "待撤销"},
            ).json()
            task_id = created["data"]["task_id"]

            response = client.post(
                f"{GATEWAY}/delete-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="c2"),
                json={"task_id": task_id},
            )
            assert response.status_code == 200, response.text

            plan = client.get(
                f"/api/v1/pregnancies/{pregnancy_id}/plan", headers=public
            ).json()
            assert all(task["id"] != task_id for task in plan["tasks"])

    def test_refuses_a_task_outside_the_session_pregnancy(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)
            other_account, other_phone, other_family, other_pregnancy, other_public = _scope(client)
            outsider_task = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent_headers(
                    other_account, other_family, other_pregnancy, call_id="c3"
                ),
                json={"title": "别人家的任务"},
            ).json()["data"]["task_id"]

            response = client.post(
                f"{GATEWAY}/delete-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="c4"),
                json={"task_id": outsider_task},
            )
            assert response.status_code == 403, response.text


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

    def test_delete_record_removes_it(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)
            record_id = client.post(
                f"{GATEWAY}/create-record",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="r2"),
                json={"record_type": "note", "content": "待撤销"},
            ).json()["data"]["record_id"]

            response = client.post(
                f"{GATEWAY}/delete-record",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="r3"),
                json={"record_id": record_id},
            )
            assert response.status_code == 200, response.text

            records = client.get(
                f"/api/v1/pregnancies/{pregnancy_id}/records", headers=public
            ).json()
            assert all(record["id"] != record_id for record in records["records"])


class TestPermissionTiersStayDistinct:
    """把新建放进「直接执行」档，不能顺手把「执行前确认」档也放开。"""

    def test_update_task_still_requires_approval(self) -> None:
        with TestClient(create_app()) as client:
            account_id, phone, family_id, pregnancy_id, public = _scope(client)
            task_id = client.post(
                f"{GATEWAY}/create-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t1"),
                json={"title": "先建一条"},
            ).json()["data"]["task_id"]

            response = client.post(
                f"{GATEWAY}/update-task",
                headers=_agent_headers(account_id, family_id, pregnancy_id, call_id="t2"),
                json={"task_id": task_id, "action": "complete", "expected_version": 1},
            )
            assert response.status_code == 409, response.text
            assert response.json()["error"]["code"] == "approval_required"
