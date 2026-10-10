"""create_checkup_report：AIM 读完一张产检报告，一次建好报告和「想问医生」。

报告与问题是一批：要么一起写进去，要么一条都不写；撤销也是整批撤。
"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings

GATEWAY = "/internal/agent-tools"
JPEG = b"\xff\xd8\xff\xe0" + b"0" * 2000


def _headers(account_id, family_id, pregnancy_id, call_id):
    return {
        "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
        "Actor-Account-Id": account_id,
        "Family-Id": family_id,
        "Pregnancy-Id": pregnancy_id,
        "Eve-Session-Id": f"eve-report-{account_id}",
        "Idempotency-Key": call_id,
    }


def _scope(client: TestClient):
    account_id = str(uuid4())
    phone = "136" + str(int(UUID(account_id)) % 10**8).zfill(8)
    token = issue_session_token(UUID(account_id), phone, get_settings().auth_secret)
    public = {"Authorization": f"Bearer {token}"}
    family = client.post(
        "/api/v1/families", headers=public, json={"name": "报告家庭", "role": "mother"}
    ).json()
    pregnancy = client.post(
        f"/api/v1/families/{family['id']}/pregnancies",
        headers=public,
        json={"due_date": "2027-01-12"},
    ).json()
    return account_id, family["id"], pregnancy["id"], public


def _upload(client: TestClient, public, pregnancy_id) -> str:
    response = client.post(
        f"/api/v1/pregnancies/{pregnancy_id}/attachments",
        headers={**public, "Content-Type": "image/jpeg"},
        content=JPEG,
    )
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _records(client: TestClient, pregnancy_id, public) -> list[dict]:
    return client.get(
        f"/api/v1/pregnancies/{pregnancy_id}/records", headers=public
    ).json()["records"]


def _report(**overrides):
    body = {
        "date": "2026-10-03",
        "hospital": "杭州市妇产科医院",
        "metrics": {"fetal_heart_rate": 145, "fundal_height_cm": 28},
        "other_items": [
            {"name": "尿蛋白", "value": "+", "reference": "阴性", "flag": "abnormal"},
            {"name": "白细胞", "value": "11.2", "unit": "10^9/L", "flag": "high"},
        ],
        "follow_up_questions": ["尿蛋白一个加号要紧吗？", "白细胞偏高要复查吗？"],
        "approved": True,
    }
    body.update(overrides)
    return body


class TestCreateCheckupReport:
    def test_needs_approval_first(self) -> None:
        """报告单上的数字是模型读出来的，先让用户在卡片上看一眼再存。"""
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)

            response = client.post(
                f"{GATEWAY}/create-checkup-report",
                headers=_headers(account_id, family_id, pregnancy_id, "r0"),
                json=_report(approved=False),
            )

            assert response.status_code == 409
            assert response.json()["error"]["code"] == "approval_required"
            assert _records(client, pregnancy_id, public) == []

    def test_creates_the_report_and_its_questions_together(self) -> None:
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)
            photo = _upload(client, public, pregnancy_id)

            response = client.post(
                f"{GATEWAY}/create-checkup-report",
                headers=_headers(account_id, family_id, pregnancy_id, "r1"),
                json=_report(attachment_ids=[photo], doctor_advice="两周后复查尿常规"),
            )
            assert response.status_code == 200, response.text
            body = response.json()
            data = body["data"]
            assert data["title"] == "10月3日 产检报告"
            assert data["question_count"] == 2
            assert len(data["record_ids"]) == 3
            assert data["record_ids"][0] == data["record_id"]
            assert body["summary"] == "已记下 10月3日产检报告，并攒了 2 个想问医生的问题"

            records = {r["id"]: r for r in _records(client, pregnancy_id, public)}
            assert set(records) == set(data["record_ids"])

            report = records[data["record_id"]]
            assert report["type"] == "checkup"
            assert report["title"] == "10月3日 产检报告"
            assert report["visibility"] == "family"
            assert report["attachment_refs"] == [photo]
            # 报告日期当天上午 9 点（上海时间），即 UTC 01:00。
            assert datetime.fromisoformat(report["occurred_at"]).isoformat() == (
                "2026-10-03T01:00:00+00:00"
            )
            structured = report["structured_data"]
            assert structured["hospital"] == "杭州市妇产科医院"
            assert structured["doctor_advice"] == "两周后复查尿常规"
            # 没读到的段落不写空串占位。
            assert "result" not in structured and "exam_items" not in structured
            assert structured["metrics"] == {"fetal_heart_rate": 145, "fundal_height_cm": 28}
            assert structured["other_items"][0] == {
                "name": "尿蛋白", "value": "+", "reference": "阴性", "flag": "abnormal"
            }
            assert structured["other_items"][1]["unit"] == "10^9/L"

            questions = [records[i] for i in data["record_ids"][1:]]
            assert [q["content"] for q in questions] == [
                "尿蛋白一个加号要紧吗？", "白细胞偏高要复查吗？"
            ]
            for question in questions:
                assert question["type"] == "question"
                assert question["visibility"] == "family"
                assert question["structured_data"] == {
                    "answered": False, "report_id": data["record_id"]
                }

            # 照片挂到了报告上，别的记录不能再挂它。
            again = client.post(
                f"{GATEWAY}/create-record",
                headers=_headers(account_id, family_id, pregnancy_id, "r1b"),
                json={"record_type": "note", "content": "再挂一次", "attachment_ids": [photo]},
            )
            assert again.status_code == 409

    def test_a_report_without_questions_is_fine(self) -> None:
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)

            response = client.post(
                f"{GATEWAY}/create-checkup-report",
                headers=_headers(account_id, family_id, pregnancy_id, "r2"),
                json={"date": "2026-10-03", "metrics": {"hemoglobin": 112}, "approved": True},
            )

            assert response.status_code == 200, response.text
            data = response.json()["data"]
            assert data["question_count"] == 0
            assert data["record_ids"] == [data["record_id"]]
            assert response.json()["summary"] == "已记下 10月3日产检报告"
            [report] = _records(client, pregnancy_id, public)
            assert report["structured_data"] == {"metrics": {"hemoglobin": 112}}

    def test_an_invalid_report_writes_nothing(self) -> None:
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)

            bad_item = client.post(
                f"{GATEWAY}/create-checkup-report",
                headers=_headers(account_id, family_id, pregnancy_id, "r3"),
                json=_report(other_items=[{"name": "尿蛋白", "value": "+", "flag": "weird"}]),
            )
            # 领域层也拦：Pydantic 放过的空白名字，到领域校验被拒。
            blank_name = client.post(
                f"{GATEWAY}/create-checkup-report",
                headers=_headers(account_id, family_id, pregnancy_id, "r3b"),
                json=_report(other_items=[{"name": "   ", "value": "+"}]),
            )

            assert bad_item.status_code == 422, bad_item.text
            assert blank_name.status_code == 409, blank_name.text
            assert _records(client, pregnancy_id, public) == []

    def test_a_bad_question_rolls_back_the_report_too(self) -> None:
        """报告先写、问题后写；问题被领域校验拒掉时，已经写下的报告也要撤回。"""
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)
            photo = _upload(client, public, pregnancy_id)

            response = client.post(
                f"{GATEWAY}/create-checkup-report",
                headers=_headers(account_id, family_id, pregnancy_id, "r4"),
                json=_report(
                    attachment_ids=[photo],
                    follow_up_questions=["尿蛋白一个加号要紧吗？", "   "],
                ),
            )

            assert response.status_code == 409, response.text
            assert _records(client, pregnancy_id, public) == []
            # 照片也没有被挂走，修好后重试还能用它。
            retry = client.post(
                f"{GATEWAY}/create-checkup-report",
                headers=_headers(account_id, family_id, pregnancy_id, "r4b"),
                json=_report(attachment_ids=[photo]),
            )
            assert retry.status_code == 200, retry.text

    def test_at_most_five_questions(self) -> None:
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)

            response = client.post(
                f"{GATEWAY}/create-checkup-report",
                headers=_headers(account_id, family_id, pregnancy_id, "r5"),
                json=_report(follow_up_questions=[f"问题 {i}" for i in range(6)]),
            )

            assert response.status_code == 422
            assert _records(client, pregnancy_id, public) == []

    def test_undo_removes_the_report_and_its_questions(self) -> None:
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)
            created = client.post(
                f"{GATEWAY}/create-checkup-report",
                headers=_headers(account_id, family_id, pregnancy_id, "r6"),
                json=_report(),
            ).json()
            assert len(_records(client, pregnancy_id, public)) == 3

            undone = client.post(
                f"{GATEWAY}/undo-operation",
                headers=_headers(account_id, family_id, pregnancy_id, "u6"),
                json={"operation_id": created["operation_id"]},
            )

            assert undone.status_code == 200, undone.text
            assert _records(client, pregnancy_id, public) == []

    def test_undo_still_works_when_a_question_was_already_deleted(self) -> None:
        """用户先在资料库删掉了其中一个问题，再撤销整份报告：剩下的照样删干净。"""
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)
            created = client.post(
                f"{GATEWAY}/create-checkup-report",
                headers=_headers(account_id, family_id, pregnancy_id, "r7"),
                json=_report(),
            ).json()
            question_id = created["data"]["record_ids"][1]
            deleted = client.delete(
                f"/api/v1/pregnancies/{pregnancy_id}/records/{question_id}", headers=public
            )
            assert deleted.status_code == 204, deleted.text

            undone = client.post(
                f"/api/v1/agent/operations/{created['operation_id']}/undo", headers=public
            )

            assert undone.status_code == 200, undone.text
            assert _records(client, pregnancy_id, public) == []

    def test_undo_of_a_single_record_still_works(self) -> None:
        """旧的撤销记录只有 data.record_id，没有 record_ids，照样能撤。"""
        with TestClient(create_app()) as client:
            account_id, family_id, pregnancy_id, public = _scope(client)
            created = client.post(
                f"{GATEWAY}/create-record",
                headers=_headers(account_id, family_id, pregnancy_id, "r8"),
                json={"record_type": "note", "content": "记得带既往报告"},
            ).json()
            assert "record_ids" not in created["data"]

            undone = client.post(
                f"{GATEWAY}/undo-operation",
                headers=_headers(account_id, family_id, pregnancy_id, "u8"),
                json={"operation_id": created["operation_id"]},
            )

            assert undone.status_code == 200, undone.text
            assert _records(client, pregnancy_id, public) == []
