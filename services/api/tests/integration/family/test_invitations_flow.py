from __future__ import annotations

import asyncio
from uuid import UUID

from fastapi.testclient import TestClient
from sqlalchemy import text

from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings
from aim_api.platform.database.session import create_database

from family_helpers import add_pregnancy, invite, new_phone, register


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


def test_a_new_account_sees_the_invitation_and_joins() -> None:
    from family_helpers import my_invitations

    with TestClient(create_app()) as client:
        mother = register(client, nickname="阿敏")
        add_pregnancy(client, mother)
        father = register(client, role="father")
        own_family = father.family_id
        invitation_id = invite(client, mother, father.phone, role="father")

        [seen] = my_invitations(client, father)
        assert seen["id"] == invitation_id
        assert seen["family_name"] == "我的家庭" and seen["inviter_name"] == "阿敏"
        assert seen["role"] == "father" and seen["can_accept"] is True

        accepted = client.post(f"/api/v1/me/invitations/{invitation_id}/accept", headers=father.headers)
        assert accepted.status_code == 200, accepted.text
        assert accepted.json() == {
            "account_id": father.account_id,
            "family_id": mother.family_id,
            "pregnancy_id": mother.pregnancy_id,
            "role": "father",
        }
        me = client.get("/api/v1/me", headers=father.headers).json()
        assert me["family_id"] == mother.family_id
        assert asyncio.run(_rows("SELECT id FROM families WHERE id = :f", f=UUID(own_family))) == []
        kinds = asyncio.run(
            _rows("SELECT kind, subject_account_id FROM family_events WHERE family_id = :f", f=UUID(mother.family_id))
        )
        assert kinds == [("member_joined", UUID(father.account_id))]
        assert my_invitations(client, father) == []


def test_a_family_with_content_cannot_be_left_behind_by_accepting() -> None:
    from family_helpers import add_record, my_invitations

    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        father = register(client, role="father")
        add_pregnancy(client, father)
        add_record(client, father)
        invitation_id = invite(client, mother, father.phone)

        [seen] = my_invitations(client, father)
        assert seen["can_accept"] is False and "记录" in seen["blocked_reason"]
        refused = client.post(f"/api/v1/me/invitations/{invitation_id}/accept", headers=father.headers)
        assert refused.status_code == 409
        assert client.get("/api/v1/me", headers=father.headers).json()["family_id"] == father.family_id


def test_declined_invitations_stay_acceptable_but_revoked_ones_do_not() -> None:
    from family_helpers import my_invitations

    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        father = register(client, role="father")
        first = invite(client, mother, father.phone)
        assert client.post(f"/api/v1/me/invitations/{first}/decline", headers=father.headers).status_code == 204
        [seen] = my_invitations(client, father)
        assert seen["status"] == "declined"

        grandma = register(client, role="other_caregiver")
        second = invite(client, mother, grandma.phone, role="other_caregiver")
        revoked = client.delete(f"/api/v1/families/{mother.family_id}/invitations/{second}", headers=mother.headers)
        assert revoked.status_code == 204
        late = client.post(f"/api/v1/me/invitations/{second}/accept", headers=grandma.headers)
        assert late.status_code == 409 and "撤回" in late.json()["error"]["message"]

        assert client.post(f"/api/v1/me/invitations/{first}/accept", headers=father.headers).status_code == 200


def test_only_the_inviter_or_admin_can_revoke() -> None:
    from family_helpers import join

    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        father = register(client, role="father")
        join(client, mother, father)
        grandma_phone = new_phone()
        invitation_id = invite(client, mother, grandma_phone, role="other_caregiver")
        denied = client.delete(f"/api/v1/families/{mother.family_id}/invitations/{invitation_id}", headers=father.headers)
        assert denied.status_code == 403


def test_a_family_with_only_the_initial_plan_still_counts_as_empty() -> None:
    from family_helpers import my_invitations

    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        father = register(client, role="father")
        add_pregnancy(client, father)
        invite(client, mother, father.phone)
        [seen] = my_invitations(client, father)
        assert seen["can_accept"] is True
