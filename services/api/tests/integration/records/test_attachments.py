from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings

JPEG = b"\xff\xd8\xff\xe0" + b"0" * 2000


def _phone(account_id: str) -> str:
    return "137" + str(int(UUID(account_id)) % 10**8).zfill(8)


def _family(client: TestClient):
    """返回 (请求头, 孕期编号, 账号编号, 家庭编号)。"""
    account_id = str(uuid4())
    token = issue_session_token(UUID(account_id), _phone(account_id), get_settings().auth_secret)
    headers = {"Authorization": f"Bearer {token}"}
    family = client.post(
        "/api/v1/families", headers=headers, json={"name": "附件家庭", "role": "mother"}
    ).json()
    pregnancy = client.post(
        f"/api/v1/families/{family['id']}/pregnancies",
        headers=headers,
        json={"due_date": "2027-01-12"},
    ).json()
    return headers, pregnancy["id"], account_id, family["id"]


def _upload(client, headers, pregnancy_id, body=JPEG, media_type="image/jpeg"):
    return client.post(
        f"/api/v1/pregnancies/{pregnancy_id}/attachments",
        headers={**headers, "Content-Type": media_type},
        content=body,
    )


def test_upload_then_read_back_the_same_bytes() -> None:
    with TestClient(create_app()) as client:
        headers, pregnancy_id, *_ = _family(client)
        uploaded = _upload(client, headers, pregnancy_id)
        assert uploaded.status_code == 201, uploaded.text
        body = uploaded.json()
        assert body["media_type"] == "image/jpeg" and body["byte_size"] == len(JPEG)

        fetched = client.get(f"/api/v1/attachments/{body['id']}", headers=headers)
        assert fetched.status_code == 200
        assert fetched.content == JPEG
        assert fetched.headers["content-type"] == "image/jpeg"
        assert "immutable" in fetched.headers["cache-control"]


def test_rejects_wrong_type_and_oversize() -> None:
    with TestClient(create_app()) as client:
        headers, pregnancy_id, *_ = _family(client)
        assert _upload(client, headers, pregnancy_id, b"%PDF", "application/pdf").status_code == 415
        huge = b"0" * (2 * 1024 * 1024 + 1)
        assert _upload(client, headers, pregnancy_id, huge).status_code == 413


def test_other_families_cannot_see_it() -> None:
    with TestClient(create_app()) as client:
        headers, pregnancy_id, *_ = _family(client)
        other_headers, *_ = _family(client)
        attachment_id = _upload(client, headers, pregnancy_id).json()["id"]
        assert (
            client.get(f"/api/v1/attachments/{attachment_id}", headers=other_headers).status_code
            == 404
        )
        assert client.get(f"/api/v1/attachments/{uuid4()}", headers=headers).status_code == 404


def test_cannot_upload_into_someone_elses_pregnancy() -> None:
    with TestClient(create_app()) as client:
        _, pregnancy_id, *_ = _family(client)
        other_headers, *_ = _family(client)
        assert _upload(client, other_headers, pregnancy_id).status_code == 403


GATEWAY = "/internal/agent-tools"


def _agent(scope, call_id: str) -> dict[str, str]:
    _, pregnancy_id, account_id, family_id = scope
    return {
        "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
        "Actor-Account-Id": account_id,
        "Family-Id": family_id,
        "Pregnancy-Id": pregnancy_id,
        "Eve-Session-Id": f"eve-attach-{account_id}",
        "Idempotency-Key": call_id,
    }


def test_agent_attaches_the_report_photo_to_the_checkup_record() -> None:
    with TestClient(create_app()) as client:
        scope = _family(client)
        headers, pregnancy_id, *_ = scope
        attachment_id = _upload(client, headers, pregnancy_id).json()["id"]

        created = client.post(
            f"{GATEWAY}/create-record",
            headers=_agent(scope, "r1"),
            json={
                "record_type": "checkup",
                "structured_data": {
                    "hospital": "杭州市妇产科医院",
                    "exam_items": "",
                    "result": "",
                    "doctor_advice": "注意补铁",
                    "metrics": {"hemoglobin": 112},
                },
                "attachment_ids": [attachment_id],
            },
        )
        assert created.status_code == 200, created.text
        assert created.json()["data"]["attachment_count"] == 1
        record_id = created.json()["data"]["record_id"]

        records = client.get(f"/api/v1/pregnancies/{pregnancy_id}/records", headers=headers).json()
        record = next(r for r in records["records"] if r["id"] == record_id)
        assert record["attachment_refs"] == [attachment_id]


def test_a_photo_cannot_be_attached_twice_or_across_families() -> None:
    with TestClient(create_app()) as client:
        scope = _family(client)
        headers, pregnancy_id, *_ = scope
        other_headers, other_pregnancy, *_ = _family(client)
        mine = _upload(client, headers, pregnancy_id).json()["id"]
        theirs = _upload(client, other_headers, other_pregnancy).json()["id"]
        agent = _agent(scope, "r2")
        note = {"record_type": "note", "content": "存档"}

        first = client.post(
            f"{GATEWAY}/create-record", headers=agent, json={**note, "attachment_ids": [mine]}
        )
        assert first.status_code == 200, first.text
        again = client.post(
            f"{GATEWAY}/create-record",
            headers={**agent, "Idempotency-Key": "r3"},
            json={**note, "attachment_ids": [mine]},
        )
        assert again.status_code == 409
        assert "已经挂在别的记录上" in again.json()["error"]["message"]
        foreign = client.post(
            f"{GATEWAY}/create-record",
            headers={**agent, "Idempotency-Key": "r4"},
            json={**note, "attachment_ids": [theirs]},
        )
        assert foreign.status_code == 409
        assert "找不到这张图片" in foreign.json()["error"]["message"]


RECORDS = "/api/v1/pregnancies/{}/records"


def _note(**extra):
    return {
        "type": "note",
        "occurred_at": "2026-10-03T01:00:00Z",
        "visibility": "family",
        "content": "化验单",
        "structured_data": {},
        **extra,
    }


def test_app_attaches_uploaded_photos_when_creating_a_record() -> None:
    """App 先上传、再带编号建记录。此前 REST 不收 attachment_ids，pydantic 静默丢掉。"""
    with TestClient(create_app()) as client:
        headers, pregnancy_id, *_ = _family(client)
        attachment_id = _upload(client, headers, pregnancy_id).json()["id"]

        created = client.post(
            RECORDS.format(pregnancy_id),
            headers=headers,
            json=_note(attachment_ids=[attachment_id]),
        )

        assert created.status_code == 201, created.text
        assert created.json()["attachment_refs"] == [attachment_id]


def test_app_cannot_attach_another_familys_photo() -> None:
    with TestClient(create_app()) as client:
        headers, pregnancy_id, *_ = _family(client)
        other_headers, other_pregnancy, *_ = _family(client)
        theirs = _upload(client, other_headers, other_pregnancy).json()["id"]

        created = client.post(
            RECORDS.format(pregnancy_id), headers=headers, json=_note(attachment_ids=[theirs])
        )

        # RecordValidationError 经 _translate 映射为 409。
        assert created.status_code == 409, created.text
        assert "找不到这张图片" in created.text


def test_app_cannot_attach_more_than_four_photos() -> None:
    with TestClient(create_app()) as client:
        headers, pregnancy_id, *_ = _family(client)
        ids = [_upload(client, headers, pregnancy_id).json()["id"] for _ in range(5)]

        created = client.post(
            RECORDS.format(pregnancy_id), headers=headers, json=_note(attachment_ids=ids)
        )

        assert created.status_code == 422, created.text
