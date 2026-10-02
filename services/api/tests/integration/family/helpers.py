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
    return person.pregnancy_id


def invite(client: TestClient, inviter: Person, phone: str, role: str = "father") -> str:
    response = client.post(
        f"/api/v1/families/{inviter.family_id}/invitations",
        json={"invitee_phone": phone, "role": role},
        headers=inviter.headers,
    )
    assert response.status_code == 201, response.text
    return response.json()["invitation_id"]
