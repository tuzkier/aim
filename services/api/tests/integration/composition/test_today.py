from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings


def _headers(account_id: str, phone: str) -> dict[str, str]:
    token = issue_session_token(UUID(account_id), phone, get_settings().auth_secret)
    return {"Authorization": f"Bearer {token}"}


def _phone(account_id: str) -> str:
    return "138" + str(int(UUID(account_id)) % 10**8).zfill(8)


def test_today_priority_follows_task_state_without_copying_tasks() -> None:
    account_id = str(uuid4())
    phone = _phone(account_id)
    headers = _headers(account_id, phone)
    with TestClient(create_app()) as client:
        family = client.post(
            "/api/v1/families", headers=headers, json={"name": "Today 家庭", "role": "mother"}
        ).json()
        pregnancy = client.post(
            f"/api/v1/families/{family['id']}/pregnancies",
            headers=headers,
            json={"due_date": "2027-01-12"},
        ).json()
        plan = client.post(
            f"/api/v1/pregnancies/{pregnancy['id']}/plan",
            headers=headers,
            json={"as_of": "2026-08-14"},
        )
        assert plan.status_code == 201, plan.text
        assert [task["source_id"] for task in plan.json()["tasks"]] == [
            "ultrasound",
            "materials",
            "records",
            "benefits",
        ]

        today = client.get(
            f"/api/v1/pregnancies/{pregnancy['id']}/today?as_of=2026-08-14", headers=headers
        )
        assert today.status_code == 200, today.text
        assert today.json()["priority_task"]["source_id"] == "ultrasound"

        ultrasound_id = plan.json()["tasks"][0]["id"]
        scheduled = client.post(
            f"/api/v1/tasks/{ultrasound_id}/schedule",
            headers=headers,
            json={"expected_version": 1, "scheduled_for": "2026-08-19T09:30:00Z"},
        )
        assert scheduled.status_code == 200, scheduled.text

        after = client.get(
            f"/api/v1/pregnancies/{pregnancy['id']}/today?as_of=2026-08-14", headers=headers
        )
        assert after.json()["priority_task"]["source_id"] == "materials"
        assert (
            sum(task["source_id"] == "ultrasound" for task in after.json()["upcoming_tasks"]) == 1
        )
