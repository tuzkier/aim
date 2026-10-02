from __future__ import annotations

import asyncio
from uuid import UUID

from fastapi.testclient import TestClient
from sqlalchemy import text

from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings
from aim_api.platform.database.session import create_database

from .helpers import add_pregnancy, invite, new_phone, register


async def _rows(sql: str, **params) -> list:
    database = create_database(get_settings().database_url)
    try:
        async with database.session() as session:
            return list((await session.execute(text(sql), params)).all())
    finally:
        await database.dispose()


def test_inviting_the_same_phone_again_revokes_the_old_invitation() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        phone = new_phone()
        first = invite(client, mother, phone)
        second = invite(client, mother, phone)
        statuses = dict(
            asyncio.run(
                _rows(
                    "SELECT id, status FROM family_invitations WHERE id IN (:a, :b)",
                    a=UUID(first),
                    b=UUID(second),
                )
            )
        )
        assert statuses == {UUID(first): "revoked", UUID(second): "pending"}


def test_an_existing_account_is_not_added_as_a_half_member() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        father = register(client, role="father")
        invite(client, mother, father.phone)
        family = client.get(f"/api/v1/families/{mother.family_id}", headers=mother.headers).json()
        assert [m["account_id"] for m in family["members"]] == [mother.account_id]
