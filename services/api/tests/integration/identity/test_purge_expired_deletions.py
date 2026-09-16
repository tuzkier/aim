from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from fastapi.testclient import TestClient
from sqlalchemy import text

from aim_api.bootstrap import create_app
from aim_api.contexts.identity.application.commands import purge_expired_deletions
from aim_api.platform.config.settings import get_settings
from aim_api.platform.database.session import create_database

PASSWORD = "a-good-password"


def _phone() -> str:
    return "138" + str(int(uuid4()) % 10**8).zfill(8)


def _register(
    client: TestClient, phone: str, role: str = "mother", due_date: str | None = None
) -> dict:
    payload: dict = {"phone": phone, "password": PASSWORD, "role": role}
    if due_date is not None:
        # 注册不带预产期就不建孕期，pregnancy_id 会是 null。
        payload["due_date"] = due_date
    response = client.post("/api/v1/auth/register", json=payload)
    assert response.status_code == 201, response.text
    return response.json()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _request_deletion(client: TestClient, session: dict) -> None:
    response = client.post(
        "/api/v1/auth/deletion-request",
        json={"password": PASSWORD},
        headers=_auth(session["token"]),
    )
    assert response.status_code == 204, response.text


async def _run_purge(now: datetime, dry_run: bool = False):
    database = create_database(get_settings().database_url)
    try:
        async with database.session() as session:
            return await purge_expired_deletions.execute(session, now=now, dry_run=dry_run)
    finally:
        # 每次 asyncio.run 都是新事件循环，引擎不释放会留下挂在旧循环上的连接。
        await database.dispose()


async def _count(sql: str, **params) -> int:
    database = create_database(get_settings().database_url)
    try:
        async with database.session() as session:
            return int(await session.scalar(text(sql), params) or 0)
    finally:
        await database.dispose()


def _later() -> datetime:
    return datetime.now(UTC) + timedelta(days=31)


def test_sole_member_family_is_deleted_entirely() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        session = _register(client, _phone())
        headers = _auth(session["token"])
        # 造一条记录和一份计划，验证它们跟着家庭一起消失。
        pregnancy = client.post(
            f"/api/v1/families/{session['family_id']}/pregnancies",
            json={"due_date": "2027-03-01"},
            headers=headers,
        )
        assert pregnancy.status_code == 201, pregnancy.text
        pregnancy_id = pregnancy.json()["id"]
        record = client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/records",
            json={
                "type": "note",
                "occurred_at": "2026-09-16T08:00:00Z",
                "visibility": "family",
                "title": "t",
                "content": "c",
                "structured_data": {},
            },
            headers=headers,
        )
        assert record.status_code == 201, record.text
        _request_deletion(client, session)

    summaries = asyncio.run(_run_purge(_later()))
    mine = [s for s in summaries if s.account_id == UUID(session["account_id"])]
    assert len(mine) == 1
    assert mine[0].families_deleted == 1 and mine[0].families_anonymized == 0

    account_id = UUID(session["account_id"])
    assert asyncio.run(_count("SELECT count(*) FROM accounts WHERE id = :id", id=account_id)) == 0
    assert (
        asyncio.run(
            _count("SELECT count(*) FROM families WHERE id = :id", id=UUID(session["family_id"]))
        )
        == 0
    )
    assert (
        asyncio.run(
            _count("SELECT count(*) FROM records WHERE pregnancy_id = :id", id=UUID(pregnancy_id))
        )
        == 0
    )
    assert (
        asyncio.run(
            _count("SELECT count(*) FROM pregnancies WHERE id = :id", id=UUID(pregnancy_id))
        )
        == 0
    )


def test_family_with_other_members_is_kept_and_anonymized() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        mother = _register(client, _phone(), due_date="2027-03-01")
        mother_headers = _auth(mother["token"])
        # 邀请响应不回手机号，所以先把它留在本地。
        father_phone = _phone()
        invite = client.post(
            f"/api/v1/families/{mother['family_id']}/invitations",
            json={"invitee_phone": father_phone, "role": "father"},
            headers=mother_headers,
        )
        assert invite.status_code == 201, invite.text
        token = invite.json()["token"]
        father = _register(client, father_phone, role="father")
        accept = client.post(
            f"/api/v1/family-invitations/{token}/accept", headers=_auth(father["token"])
        )
        assert accept.status_code == 200, accept.text

        # 妈妈是家庭创建人，还给自己指派了一条待办。
        plan = client.post(
            f"/api/v1/pregnancies/{mother['pregnancy_id']}/tasks",
            json={"title": "买叶酸"},
            headers=mother_headers,
        )
        assert plan.status_code == 201, plan.text
        task = plan.json()
        assign = client.post(
            f"/api/v1/tasks/{task['id']}/assign",
            json={"expected_version": task["version"], "assigned_member_id": mother["account_id"]},
            headers=mother_headers,
        )
        assert assign.status_code == 200, assign.text
        # 她还写了一条私密记录和一条全家可见的记录。
        for visibility in ("private", "family"):
            record = client.post(
                f"/api/v1/pregnancies/{mother['pregnancy_id']}/records",
                json={
                    "type": "note",
                    "occurred_at": "2026-09-16T08:00:00Z",
                    "visibility": visibility,
                    "title": visibility,
                    "content": "c",
                    "structured_data": {},
                },
                headers=mother_headers,
            )
            assert record.status_code == 201, record.text
        _request_deletion(client, mother)

    summaries = asyncio.run(_run_purge(_later()))
    mine = [s for s in summaries if s.account_id == UUID(mother["account_id"])]
    assert mine and mine[0].families_anonymized == 1 and mine[0].families_deleted == 0

    # 私密记录没人能再看，删掉；全家可见的记录留给家里人。
    author = UUID(mother["account_id"])
    assert (
        asyncio.run(
            _count(
                "SELECT count(*) FROM records "
                "WHERE author_account_id = :author AND visibility = 'private'",
                author=author,
            )
        )
        == 0
    )
    assert (
        asyncio.run(
            _count(
                "SELECT count(*) FROM records "
                "WHERE author_account_id = :author AND visibility = 'family'",
                author=author,
            )
        )
        == 1
    )

    family_id = UUID(mother["family_id"])
    assert (
        asyncio.run(
            _count("SELECT count(*) FROM accounts WHERE id = :id", id=UUID(mother["account_id"]))
        )
        == 0
    )
    assert asyncio.run(_count("SELECT count(*) FROM families WHERE id = :id", id=family_id)) == 1
    assert (
        asyncio.run(
            _count(
                "SELECT count(*) FROM families WHERE id = :id AND created_by = :father",
                id=family_id,
                father=UUID(father["account_id"]),
            )
        )
        == 1
    )
    assert (
        asyncio.run(
            _count(
                "SELECT count(*) FROM tasks WHERE id = :id AND assigned_member_id IS NULL",
                id=UUID(task["id"]),
            )
        )
        == 1
    )


def test_pending_invitee_does_not_count_as_a_remaining_member() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        # 爸爸先注册，这样邀请他时会立刻写入一条 pending 的成员行。
        father = _register(client, _phone(), role="father")
        mother = _register(client, _phone(), due_date="2027-03-01")
        invite = client.post(
            f"/api/v1/families/{mother['family_id']}/invitations",
            json={"invitee_phone": father["phone"], "role": "father"},
            headers=_auth(mother["token"]),
        )
        assert invite.status_code == 201, invite.text
        # 爸爸始终没有接受。
        _request_deletion(client, mother)

    summaries = asyncio.run(_run_purge(_later()))
    mine = [s for s in summaries if s.account_id == UUID(mother["account_id"])]
    assert mine and mine[0].families_deleted == 1 and mine[0].families_anonymized == 0

    assert (
        asyncio.run(
            _count("SELECT count(*) FROM families WHERE id = :id", id=UUID(mother["family_id"]))
        )
        == 0
    )
    assert (
        asyncio.run(
            _count("SELECT count(*) FROM accounts WHERE id = :id", id=UUID(father["account_id"]))
        )
        == 1
    )


def test_accounts_still_in_grace_and_dry_run_are_untouched() -> None:
    with TestClient(create_app(settings=get_settings())) as client:
        session = _register(client, _phone())
        _request_deletion(client, session)

    account_id = UUID(session["account_id"])
    # 别的用例可能留下了已到期的账号，所以只断言「我这个」没被碰。
    early = asyncio.run(_run_purge(datetime.now(UTC) + timedelta(days=10)))
    assert all(s.account_id != account_id for s in early)

    dry = asyncio.run(_run_purge(_later(), dry_run=True))
    assert any(s.account_id == account_id for s in dry)
    assert asyncio.run(_count("SELECT count(*) FROM accounts WHERE id = :id", id=account_id)) == 1
