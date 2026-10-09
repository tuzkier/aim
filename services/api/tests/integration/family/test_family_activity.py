from __future__ import annotations

from datetime import date, timedelta

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings
from family_helpers import add_pregnancy, add_record, add_task, invite, join, new_phone, register


def _activity(client, person, **params):
    response = client.get(
        f"/api/v1/families/{person.family_id}/activity", params=params, headers=person.headers
    )
    assert response.status_code == 200, response.text
    return response.json()


def _agent_creates_task(client, person, title: str) -> None:
    response = client.post(
        "/internal/agent-tools/create-task",
        headers={
            "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
            "Actor-Account-Id": person.account_id,
            "Family-Id": person.family_id,
            "Pregnancy-Id": person.pregnancy_id,
            "Eve-Session-Id": f"eve-activity-{person.account_id}",
            "Idempotency-Key": f"act-{abs(hash(title))}",
        },
        json={"tasks": [{"title": title}]},
    )
    assert response.status_code == 200, response.text


def test_activity_merges_people_tasks_records_and_due_date_changes() -> None:
    with TestClient(create_app()) as client:
        mother = register(client, nickname="阿敏")
        add_pregnancy(client, mother)
        father = register(client, role="father", nickname="老王")
        join(client, mother, father)
        add_task(client, father, "买产褥垫")
        _agent_creates_task(client, mother, "预约产检")
        add_record(client, mother, visibility="family")
        add_record(client, mother, visibility="private")
        client.patch(
            f"/api/v1/pregnancies/{mother.pregnancy_id}",
            json={"due_date": (date.today() + timedelta(days=60)).isoformat()},
            headers=mother.headers,
        )

        items = _activity(client, father)["items"]
        kinds = [item["kind"] for item in items]
        # 新的在前；初始计划的模板待办和私密记录都不出现
        assert kinds == [
            "due_date_changed",
            "record_created",
            "task_created",
            "task_created",
            "member_joined",
        ]
        by_kind = {item["kind"]: item for item in items}
        assert by_kind["member_joined"]["actor_name"] == "老王"
        assert by_kind["record_created"]["actor_name"] == "阿敏"
        agent_task = next(i for i in items if i["kind"] == "task_created" and i["title"] == "预约产检")
        assert agent_task["via_agent"] is True and agent_task["actor_name"] == "阿敏"
        assert agent_task["target_type"] == "task" and agent_task["target_id"]


def test_completed_tasks_and_deleted_records_show_up_accordingly() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        task_id = add_task(client, mother, "买叶酸")
        version = client.get(f"/api/v1/pregnancies/{mother.pregnancy_id}/plan", headers=mother.headers).json()
        task = next(t for t in version["tasks"] if t["id"] == task_id)
        done = client.post(
            f"/api/v1/tasks/{task_id}/complete",
            json={"expected_version": task["version"]},
            headers=mother.headers,
        )
        assert done.status_code == 200, done.text
        record_id = add_record(client, mother)
        assert client.delete(f"/api/v1/pregnancies/{mother.pregnancy_id}/records/{record_id}", headers=mother.headers).status_code == 204

        items = _activity(client, mother)["items"]
        assert [i["kind"] for i in items][:2] == ["record_created", "task_completed"]
        assert items[0]["target_deleted"] is True


def test_activity_pages_backwards() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        for n in range(5):
            add_task(client, mother, f"待办{n}")
        first = _activity(client, mother, limit=3)
        assert [i["title"] for i in first["items"]] == ["待办4", "待办3", "待办2"]
        second = _activity(client, mother, limit=3, before=first["next_before"])
        assert [i["title"] for i in second["items"]] == ["待办1", "待办0"]
        assert second["next_before"] is None


def test_family_detail_marks_the_admin_and_lists_open_invitations() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        phone = new_phone()
        invite(client, mother, phone, role="other_caregiver")
        family = client.get(f"/api/v1/families/{mother.family_id}", headers=mother.headers).json()
        assert family["members"][0]["is_admin"] is True
        [invitation] = family["invitations"]
        assert invitation["phone_masked"] == phone[:3] + "****" + phone[-4:]
        assert invitation["role"] == "other_caregiver" and invitation["status"] == "pending"
        assert invitation["invited_by"] == mother.account_id


def test_member_detail_shows_their_open_tasks_and_visible_records() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        father = register(client, role="father")
        join(client, mother, father)
        add_task(client, mother, "装安全座椅", assignee=father.account_id)
        add_record(client, father, visibility="family")
        add_record(client, father, visibility="private")

        detail = client.get(
            f"/api/v1/families/{mother.family_id}/members/{father.account_id}", headers=mother.headers
        ).json()
        assert detail["member"]["account_id"] == father.account_id
        assert [t["title"] for t in detail["open_tasks"]] == ["装安全座椅"]
        assert len(detail["recent_records"]) == 1  # 别人的私密记录看不到

        mine = client.get(
            f"/api/v1/families/{mother.family_id}/members/{father.account_id}", headers=father.headers
        ).json()
        assert len(mine["recent_records"]) == 2


def test_conversation_history_only_lists_the_current_family() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        father = register(client, role="father")
        join(client, mother, father)
        created = client.post(
            "/api/v1/agent/sessions",
            json={"eve_session_id": f"eve-in-family-{father.account_id}", "title": "问问"},
            headers=father.headers,
        )
        assert created.status_code == 201, created.text
        assert len(client.get("/api/v1/agent/sessions", headers=father.headers).json()["sessions"]) == 1

        left = client.post(f"/api/v1/families/{mother.family_id}/members/me/leave", headers=father.headers)
        assert left.status_code == 200, left.text
        assert client.get("/api/v1/agent/sessions", headers=father.headers).json()["sessions"] == []
