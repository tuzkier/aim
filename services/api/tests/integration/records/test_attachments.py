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
