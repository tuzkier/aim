from __future__ import annotations

import asyncio
from uuid import UUID

from fastapi.testclient import TestClient
from sqlalchemy import text

from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings
from aim_api.platform.database.session import create_database
from family_helpers import add_pregnancy, add_record, add_task, join, register


async def _scalar(sql: str, **params):
    database = create_database(get_settings().database_url)
    try:
        async with database.session() as session:
            return await session.scalar(text(sql), params)
    finally:
        await database.dispose()


def _family(client, person):
    return client.get(f"/api/v1/families/{person.family_id}", headers=person.headers).json()


def test_admin_removes_a_member_and_cleans_up_after_them() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        father = register(client, role="father")
        join(client, mother, father)
        family_id = mother.family_id
        task = add_task(client, mother, "买叶酸", assignee=father.account_id)
        add_record(client, father, visibility="private")
        kept = add_record(client, father, visibility="family")

        removed = client.delete(
            f"/api/v1/families/{family_id}/members/{father.account_id}", headers=mother.headers
        )
        assert removed.status_code == 204, removed.text

        assert [m["account_id"] for m in _family(client, mother)["members"]] == [mother.account_id]
        assert asyncio.run(_scalar("SELECT assigned_member_id FROM tasks WHERE id = :t", t=UUID(task))) is None
        assert asyncio.run(
            _scalar(
                "SELECT count(*) FROM records WHERE author_account_id = :a AND visibility = 'private'",
                a=UUID(father.account_id),
            )
        ) == 0
        assert asyncio.run(_scalar("SELECT count(*) FROM records WHERE id = :r", r=UUID(kept))) == 1
        assert asyncio.run(
            _scalar("SELECT kind FROM family_events WHERE family_id = :f AND kind <> 'member_joined'", f=UUID(family_id))
        ) == "member_removed"

        me = client.get("/api/v1/me", headers=father.headers).json()
        assert me["family_id"] != family_id and me["pregnancy_id"] is None
        assert client.get(f"/api/v1/families/{family_id}", headers=father.headers).status_code == 403


def test_only_the_admin_can_remove_others_and_nobody_removes_themselves() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        father = register(client, role="father")
        join(client, mother, father)
        url = f"/api/v1/families/{mother.family_id}/members"
        assert client.delete(f"{url}/{mother.account_id}", headers=father.headers).status_code == 403
        assert client.delete(f"{url}/{mother.account_id}", headers=mother.headers).status_code == 409


def test_admin_leaving_hands_the_family_to_the_earliest_member() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        father = register(client, role="father")
        join(client, mother, father)
        family_id = mother.family_id

        left = client.post(f"/api/v1/families/{family_id}/members/me/leave", headers=mother.headers)
        assert left.status_code == 200, left.text
        assert left.json()["family_id"] != family_id and left.json()["pregnancy_id"] is None

        family = _family(client, father)
        assert family["created_by"] == father.account_id
        assert [m["account_id"] for m in family["members"]] == [father.account_id]


def test_the_last_member_cannot_leave() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        response = client.post(
            f"/api/v1/families/{mother.family_id}/members/me/leave", headers=mother.headers
        )
        assert response.status_code == 409
