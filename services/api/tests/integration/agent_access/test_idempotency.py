from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings


def _phone(account_id: str) -> str:
    return "138" + str(int(UUID(account_id)) % 10**8).zfill(8)


def test_write_tool_requires_approval_and_replays_same_result() -> None:
    account_id = str(uuid4())
    phone = _phone(account_id)
    public = {
        "Authorization": (
            f"Bearer {issue_session_token(UUID(account_id), phone, get_settings().auth_secret)}"
        )
    }
    with TestClient(create_app()) as client:
        family = client.post(
            "/api/v1/families", headers=public, json={"name": "幂等家庭", "role": "mother"}
        ).json()
        pregnancy = client.post(
            f"/api/v1/families/{family['id']}/pregnancies",
            headers=public,
            json={"due_date": "2027-01-12"},
        ).json()
        plan = client.post(
            f"/api/v1/pregnancies/{pregnancy['id']}/plan",
            headers=public,
            json={"as_of": "2026-08-14"},
        ).json()
        ultrasound_id = plan["tasks"][0]["id"]
        internal = {
            "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
            "Actor-Account-Id": account_id,
            "Family-Id": family["id"],
            "Pregnancy-Id": pregnancy["id"],
            "Eve-Session-Id": f"eve-idempotency-{account_id}",
            "Idempotency-Key": "update-ultrasound-1",
        }
        body = {
            "task_id": ultrasound_id,
            "expected_version": 1,
            "kind": "schedule",
            "at": "2026-08-19T09:30:00Z",
            "approved": True,
        }
        first = client.post("/internal/agent-tools/reschedule-task", headers=internal, json=body)
        assert first.status_code == 200, first.text
        second = client.post("/internal/agent-tools/reschedule-task", headers=internal, json=body)
        assert second.status_code == 200, second.text
        assert second.json()["operation_id"] == first.json()["operation_id"]

        conflict = client.post(
            "/internal/agent-tools/reschedule-task",
            headers=internal,
            json={**body, "at": "2026-08-20T09:30:00Z"},
        )
        assert conflict.status_code == 409

        unapproved = client.post(
            "/internal/agent-tools/reschedule-task",
            headers={**internal, "Idempotency-Key": "update-materials-1"},
            json={
                "task_id": plan["tasks"][1]["id"],
                "expected_version": 1,
                "kind": "delay",
                "at": "2026-08-30T09:30:00Z",
                "approved": False,
            },
        )
        assert unapproved.status_code == 409
        assert unapproved.json()["error"]["code"] == "approval_required"
