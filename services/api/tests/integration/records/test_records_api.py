from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings


def _phone(account_id: str, prefix: str = "138") -> str:
    return prefix + str(int(UUID(account_id)) % 10**8).zfill(8)


def _headers(account_id: str, phone: str) -> dict[str, str]:
    token = issue_session_token(UUID(account_id), phone, get_settings().auth_secret)
    return {"Authorization": f"Bearer {token}"}


def _create_pregnancy(client: TestClient, account_id: str, phone: str) -> tuple[str, str]:
    headers = _headers(account_id, phone)
    family = client.post(
        "/api/v1/families", headers=headers, json={"name": "孕期记录家庭", "role": "mother"}
    )
    assert family.status_code == 201, family.text
    pregnancy = client.post(
        f"/api/v1/families/{family.json()['id']}/pregnancies",
        headers=headers,
        json={"due_date": "2026-12-25"},
    )
    assert pregnancy.status_code == 201, pregnancy.text
    return family.json()["id"], pregnancy.json()["id"]


def _create_record(
    client: TestClient, pregnancy_id: str, headers: dict[str, str], **overrides: object
):
    payload = {
        "type": "symptom",
        "occurred_at": "2026-08-16T08:30:00+08:00",
        "visibility": "family",
        "title": "晨吐",
        "structured_data": {"symptoms": ["nausea"], "severity": 3, "note": "早晨明显"},
    }
    payload.update(overrides)
    return client.post(f"/api/v1/pregnancies/{pregnancy_id}/records", headers=headers, json=payload)


def test_record_endpoints_require_authentication() -> None:
    pregnancy_id = uuid4()
    record_id = uuid4()

    with TestClient(create_app()) as client:
        collection = client.get(f"/api/v1/pregnancies/{pregnancy_id}/records")
        item = client.get(f"/api/v1/pregnancies/{pregnancy_id}/records/{record_id}")
        create = client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/records",
            json={
                "type": "note",
                "occurred_at": "2026-08-16T08:30:00+08:00",
                "visibility": "private",
                "content": "未认证请求",
                "structured_data": {},
            },
        )
        update = client.patch(f"/api/v1/pregnancies/{pregnancy_id}/records/{record_id}", json={})
        delete = client.delete(f"/api/v1/pregnancies/{pregnancy_id}/records/{record_id}")
        create_task = client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/tasks", json={"title": "未认证待办"}
        )

    assert all(
        response.status_code == 401
        for response in (collection, item, create, update, delete, create_task)
    )


def test_records_create_all_types_and_validate_payloads() -> None:
    account_id = str(uuid4())
    phone = _phone(account_id)
    headers = _headers(account_id, phone)

    with TestClient(create_app()) as client:
        _, pregnancy_id = _create_pregnancy(client, account_id, phone)
        symptom = _create_record(client, pregnancy_id, headers)
        checkup = _create_record(
            client,
            pregnancy_id,
            headers,
            type="checkup",
            structured_data={
                "hospital": "市妇保",
                "exam_items": "超声",
                "result": "正常",
                "doctor_advice": "规律作息",
            },
        )
        note = _create_record(
            client,
            pregnancy_id,
            headers,
            type="note",
            content="今天精神不错",
            structured_data={},
        )
        invalid = _create_record(
            client, pregnancy_id, headers, structured_data={"symptoms": [], "severity": 7}
        )

    assert symptom.status_code == 201, symptom.text
    assert symptom.json()["attachment_refs"] == []
    assert checkup.status_code == 201, checkup.text
    assert note.status_code == 201, note.text
    assert invalid.status_code == 409


def test_records_list_orders_newest_first_and_filters_type() -> None:
    account_id = str(uuid4())
    phone = _phone(account_id)
    headers = _headers(account_id, phone)

    with TestClient(create_app()) as client:
        _, pregnancy_id = _create_pregnancy(client, account_id, phone)
        older = _create_record(
            client, pregnancy_id, headers, occurred_at="2026-08-15T08:30:00+08:00"
        )
        newest = _create_record(
            client,
            pregnancy_id,
            headers,
            type="note",
            occurred_at="2026-08-16T09:30:00+08:00",
            content="最新记录",
            structured_data={},
        )
        listed = client.get(f"/api/v1/pregnancies/{pregnancy_id}/records", headers=headers)
        filtered = client.get(
            f"/api/v1/pregnancies/{pregnancy_id}/records?type=symptom", headers=headers
        )

    assert older.status_code == 201, older.text
    assert newest.status_code == 201, newest.text
    assert listed.status_code == 200, listed.text
    assert [record["id"] for record in listed.json()["records"]][:2] == [
        newest.json()["id"],
        older.json()["id"],
    ]
    assert filtered.status_code == 200, filtered.text
    assert [record["type"] for record in filtered.json()["records"]] == ["symptom"]


def test_records_get_edit_and_soft_delete() -> None:
    account_id = str(uuid4())
    phone = _phone(account_id)
    headers = _headers(account_id, phone)

    with TestClient(create_app()) as client:
        _, pregnancy_id = _create_pregnancy(client, account_id, phone)
        created = _create_record(client, pregnancy_id, headers)
        record_id = created.json()["id"]
        fetched = client.get(f"/api/v1/pregnancies/{pregnancy_id}/records/{record_id}", headers=headers)
        edited = client.patch(
            f"/api/v1/pregnancies/{pregnancy_id}/records/{record_id}",
            headers=headers,
            json={"title": "晚间反胃", "structured_data": {"symptoms": ["nausea"], "severity": 4}},
        )
        deleted = client.delete(
            f"/api/v1/pregnancies/{pregnancy_id}/records/{record_id}", headers=headers
        )
        after_delete = client.get(
            f"/api/v1/pregnancies/{pregnancy_id}/records/{record_id}", headers=headers
        )

    assert created.status_code == 201, created.text
    assert fetched.status_code == 200, fetched.text
    assert edited.status_code == 200, edited.text
    assert edited.json()["title"] == "晚间反胃"
    assert deleted.status_code == 204, deleted.text
    assert after_delete.status_code == 404


def test_records_enforce_visibility_author_mutation_and_family_boundary() -> None:
    author_id = str(uuid4())
    member_id = str(uuid4())
    stranger_id = str(uuid4())
    author_phone = _phone(author_id)
    member_phone = _phone(member_id, "139")
    stranger_phone = _phone(stranger_id, "137")
    author_headers = _headers(author_id, author_phone)
    member_headers = _headers(member_id, member_phone)
    stranger_headers = _headers(stranger_id, stranger_phone)

    with TestClient(create_app()) as client:
        family_id, pregnancy_id = _create_pregnancy(client, author_id, author_phone)
        invitation = client.post(
            f"/api/v1/families/{family_id}/invitations",
            headers=author_headers,
            json={"invitee_phone": member_phone, "role": "father"},
        )
        accepted = client.post(
            f"/api/v1/family-invitations/{invitation.json()['token']}/accept", headers=member_headers
        )
        assert accepted.status_code == 200, accepted.text
        family_record = _create_record(client, pregnancy_id, author_headers)
        private_record = _create_record(client, pregnancy_id, author_headers, visibility="private")
        family_id_record = family_record.json()["id"]
        private_id = private_record.json()["id"]

        member_list = client.get(f"/api/v1/pregnancies/{pregnancy_id}/records", headers=member_headers)
        member_private = client.get(
            f"/api/v1/pregnancies/{pregnancy_id}/records/{private_id}", headers=member_headers
        )
        non_author_edit = client.patch(
            f"/api/v1/pregnancies/{pregnancy_id}/records/{family_id_record}",
            headers=member_headers,
            json={"title": "不应修改"},
        )
        cross_family = client.get(
            f"/api/v1/pregnancies/{pregnancy_id}/records/{family_id_record}", headers=stranger_headers
        )

    assert family_record.status_code == 201, family_record.text
    assert private_record.status_code == 201, private_record.text
    assert member_list.status_code == 200, member_list.text
    assert [record["id"] for record in member_list.json()["records"]] == [family_id_record]
    assert member_private.status_code == 404
    assert non_author_edit.status_code == 403
    assert cross_family.status_code == 403


def test_record_can_be_explicitly_converted_to_task_without_cross_family_leakage() -> None:
    author_id = str(uuid4())
    stranger_id = str(uuid4())
    author_phone = _phone(author_id)
    stranger_phone = _phone(stranger_id, "137")
    author_headers = _headers(author_id, author_phone)
    stranger_headers = _headers(stranger_id, stranger_phone)

    with TestClient(create_app()) as client:
        _, pregnancy_id = _create_pregnancy(client, author_id, author_phone)
        created_record = _create_record(client, pregnancy_id, author_headers)
        generated_plan = client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/plan", headers=author_headers, json={}
        )
        task = client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/tasks",
            headers=author_headers,
            json={
                "record_id": created_record.json()["id"],
                "title": "跟进晨吐情况",
                "description": "下次产检时咨询医生",
                "due_at": "2026-08-30T09:00:00+08:00",
            },
        )
        cross_family = client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/tasks",
            headers=stranger_headers,
            json={
                "record_id": created_record.json()["id"],
                "title": "不应越权创建",
            },
        )

    assert created_record.status_code == 201, created_record.text
    assert generated_plan.status_code == 201, generated_plan.text
    assert task.status_code == 201, task.text
    assert task.json()["source_type"] == "record"
    assert task.json()["source_id"] == created_record.json()["id"]
    assert task.json()["changed_by_actor_type"] == "account"
    assert task.json()["changed_by_actor_id"] == author_id
    assert task.json()["due_at"] == "2026-08-30T09:00:00+08:00"
    assert cross_family.status_code == 403


def test_fetal_movement_records_can_be_created_filtered_and_rejected() -> None:
    account_id = str(uuid4())
    phone = _phone(account_id)
    headers = _headers(account_id, phone)
    with TestClient(create_app()) as client:
        _, pregnancy_id = _create_pregnancy(client, account_id, phone)
        created = _create_record(
            client,
            pregnancy_id,
            headers,
            type="fetal_movement",
            title="数胎动 10 次 · 32 分钟",
            structured_data={
                "duration_seconds": 1920,
                "count": 10,
                "target": 10,
                "outcome": "reached",
                "taps": [30, 200, 400, 600, 800, 1000, 1200, 1500, 1700, 1920],
            },
        )
        rejected = _create_record(
            client,
            pregnancy_id,
            headers,
            type="fetal_movement",
            structured_data={
                "duration_seconds": 60,
                "count": 1,
                "target": 6,
                "outcome": "stopped",
                "taps": [5],
            },
        )
        listed = client.get(
            f"/api/v1/pregnancies/{pregnancy_id}/records",
            params={"type": "fetal_movement"},
            headers=headers,
        )

    assert created.status_code == 201, created.text
    assert created.json()["structured_data"]["outcome"] == "reached"
    assert rejected.status_code == 409, rejected.text
    assert listed.status_code == 200, listed.text
    assert [r["type"] for r in listed.json()["records"]] == ["fetal_movement"]
