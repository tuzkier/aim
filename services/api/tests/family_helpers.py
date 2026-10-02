"""家庭相关集成测试共用的小工具：走真实的注册接口，和 App 的路径一致。"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta
from uuid import uuid4

from fastapi.testclient import TestClient

PASSWORD = "a-good-password"


def new_phone() -> str:
    return "139" + str(int(uuid4()) % 10**8).zfill(8)


@dataclass
class Person:
    phone: str
    account_id: str
    family_id: str
    token: str
    pregnancy_id: str | None = None

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}


def register(client: TestClient, *, role: str = "mother", nickname: str | None = None) -> Person:
    """注册一个人。App 注册不带预产期，所以此时家庭是空的、没有孕期。"""
    phone = new_phone()
    payload = {"phone": phone, "password": PASSWORD, "role": role}
    if nickname:
        payload["nickname"] = nickname
    response = client.post("/api/v1/auth/register", json=payload)
    assert response.status_code == 201, response.text
    body = response.json()
    return Person(phone, body["account_id"], body["family_id"], body["token"])


def add_pregnancy(client: TestClient, person: Person, *, weeks_from_now: int = 10) -> str:
    due = (date.today() + timedelta(weeks=weeks_from_now)).isoformat()
    response = client.post(
        f"/api/v1/families/{person.family_id}/pregnancies",
        json={"due_date": due},
        headers=person.headers,
    )
    assert response.status_code == 201, response.text
    person.pregnancy_id = response.json()["id"]
    # 和 App 一样，建孕期后生成初始计划（模板待办）。
    plan = client.post(
        f"/api/v1/pregnancies/{person.pregnancy_id}/plan",
        json={"as_of": date.today().isoformat()},
        headers=person.headers,
    )
    assert plan.status_code in (200, 201), plan.text
    return person.pregnancy_id


def invite(client: TestClient, inviter: Person, phone: str, role: str = "father") -> str:
    response = client.post(
        f"/api/v1/families/{inviter.family_id}/invitations",
        json={"invitee_phone": phone, "role": role},
        headers=inviter.headers,
    )
    assert response.status_code == 201, response.text
    return response.json()["invitation_id"]


def add_record(client: TestClient, person: Person, *, visibility: str = "family") -> str:
    response = client.post(
        f"/api/v1/pregnancies/{person.pregnancy_id}/records",
        json={
            "type": "note",
            "occurred_at": "2026-09-16T08:00:00Z",
            "visibility": visibility,
            "title": visibility,
            "content": "c",
            "structured_data": {},
        },
        headers=person.headers,
    )
    assert response.status_code == 201, response.text
    return response.json()["id"]


def add_task(client: TestClient, person: Person, title: str, *, assignee: str | None = None) -> str:
    response = client.post(
        f"/api/v1/pregnancies/{person.pregnancy_id}/tasks",
        json={"title": title},
        headers=person.headers,
    )
    assert response.status_code == 201, response.text
    task = response.json()
    if assignee:
        assigned = client.post(
            f"/api/v1/tasks/{task['id']}/assign",
            json={"expected_version": task["version"], "assigned_member_id": assignee},
            headers=person.headers,
        )
        assert assigned.status_code == 200, assigned.text
    return task["id"]


def my_invitations(client: TestClient, person: Person) -> list[dict]:
    response = client.get("/api/v1/me/invitations", headers=person.headers)
    assert response.status_code == 200, response.text
    return response.json()["invitations"]


def join(client: TestClient, inviter: Person, invitee: Person, role: str = "father") -> None:
    """inviter 邀请 invitee，invitee 接受；之后 invitee 的家庭与孕期换成 inviter 的。"""
    invitation_id = invite(client, inviter, invitee.phone, role)
    response = client.post(
        f"/api/v1/me/invitations/{invitation_id}/accept", headers=invitee.headers
    )
    assert response.status_code == 200, response.text
    invitee.family_id = response.json()["family_id"]
    invitee.pregnancy_id = response.json()["pregnancy_id"]
