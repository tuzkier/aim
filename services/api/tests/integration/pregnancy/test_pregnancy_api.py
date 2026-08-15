from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings


def _headers(account_id: str, phone: str) -> dict[str, str]:
    token = issue_session_token(UUID(account_id), phone, get_settings().auth_secret)
    return {"Authorization": f"Bearer {token}"}


def _phone(account_id: str, prefix: str = "138") -> str:
    return prefix + str(int(UUID(account_id)) % 10**8).zfill(8)


def test_pregnancy_requires_family_membership_and_returns_dynamic_week() -> None:
    creator_id = str(uuid4())
    stranger_id = str(uuid4())
    creator_phone = _phone(creator_id)
    stranger_phone = _phone(stranger_id, "139")

    with TestClient(create_app()) as client:
        family = client.post(
            "/api/v1/families",
            headers=_headers(creator_id, creator_phone),
            json={"name": "孕期家庭", "role": "mother"},
        ).json()
        family_id = family["id"]

        created = client.post(
            f"/api/v1/families/{family_id}/pregnancies",
            headers=_headers(creator_id, creator_phone),
            json={"due_date": "2026-09-25"},
        )
        assert created.status_code == 201, created.text
        pregnancy_id = created.json()["id"]

        forbidden = client.get(
            f"/api/v1/pregnancies/{pregnancy_id}",
            headers=_headers(stranger_id, stranger_phone),
        )
        assert forbidden.status_code == 403

        forbidden_write = client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/facts",
            headers=_headers(stranger_id, stranger_phone),
            json={"key": "note", "value": "unauthorized", "source": "user_confirmed"},
        )
        assert forbidden_write.status_code == 403

        fetched = client.get(
            f"/api/v1/pregnancies/{pregnancy_id}",
            headers=_headers(creator_id, creator_phone),
        )
        assert fetched.status_code == 200
        assert fetched.json()["gestational_age"]["weeks"] >= 0


def test_pregnancy_can_be_created_from_last_menstrual_period() -> None:
    account_id = str(uuid4())
    phone = _phone(account_id)
    headers = _headers(account_id, phone)

    with TestClient(create_app()) as client:
        family = client.post(
            "/api/v1/families", headers=headers, json={"name": "末次月经家庭", "role": "mother"}
        ).json()
        pregnancy = client.post(
            f"/api/v1/families/{family['id']}/pregnancies",
            headers=headers,
            json={"last_menstrual_period": "2026-04-11"},
        )

    assert pregnancy.status_code == 201, pregnancy.text
    assert pregnancy.json()["due_date"] == "2027-01-16"
    assert pregnancy.json()["last_menstrual_period"] == "2026-04-11"


def test_pregnancy_date_input_requires_exactly_one_date() -> None:
    account_id = str(uuid4())
    phone = _phone(account_id)
    headers = _headers(account_id, phone)

    with TestClient(create_app()) as client:
        family = client.post(
            "/api/v1/families", headers=headers, json={"name": "日期校验家庭", "role": "mother"}
        ).json()
        base = f"/api/v1/families/{family['id']}/pregnancies"
        neither = client.post(base, headers=headers, json={})
        both = client.post(
            base,
            headers=headers,
            json={"due_date": "2027-01-16", "last_menstrual_period": "2026-04-11"},
        )

    assert neither.status_code == 422
    assert both.status_code == 422


def test_fact_conflict_is_explicit_and_does_not_change_active_value() -> None:
    account_id = str(uuid4())
    phone = _phone(account_id)

    with TestClient(create_app()) as client:
        family = client.post(
            "/api/v1/families",
            headers=_headers(account_id, phone),
            json={"name": "孕期家庭", "role": "mother"},
        ).json()
        pregnancy = client.post(
            f"/api/v1/families/{family['id']}/pregnancies",
            headers=_headers(account_id, phone),
            json={"due_date": "2026-09-25"},
        ).json()

        doctor = client.post(
            f"/api/v1/pregnancies/{pregnancy['id']}/facts",
            headers=_headers(account_id, phone),
            json={
                "key": "due_date",
                "value": "2026-09-25",
                "source": "doctor_confirmed",
            },
        )
        assert doctor.status_code == 201, doctor.text

        conflict = client.post(
            f"/api/v1/pregnancies/{pregnancy['id']}/facts",
            headers=_headers(account_id, phone),
            json={
                "key": "due_date",
                "value": "2026-10-02",
                "source": "agent_inferred",
            },
        )
        assert conflict.status_code == 201, conflict.text
        assert conflict.json()["status"] == "needs_verification"
