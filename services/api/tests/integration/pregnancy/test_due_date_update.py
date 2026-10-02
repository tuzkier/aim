from __future__ import annotations

import asyncio
from datetime import date, timedelta

from fastapi.testclient import TestClient
from sqlalchemy import text

from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings
from aim_api.platform.database.session import create_database

from family_helpers import add_pregnancy, register


async def _events(family_id: str) -> list:
    database = create_database(get_settings().database_url)
    try:
        async with database.session() as session:
            rows = await session.execute(
                text("SELECT kind, actor_account_id, payload FROM family_events WHERE family_id = :f"),
                {"f": family_id},
            )
            return list(rows.all())
    finally:
        await database.dispose()


def _patch(client, person, due: date):
    return client.patch(
        f"/api/v1/pregnancies/{person.pregnancy_id}",
        json={"due_date": due.isoformat()},
        headers=person.headers,
    )


def test_moving_the_due_date_updates_the_week_and_is_logged() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother, weeks_from_now=10)
        before = client.get(f"/api/v1/pregnancies/{mother.pregnancy_id}", headers=mother.headers).json()

        new_due = date.today() + timedelta(days=62)
        response = _patch(client, mother, new_due)
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["due_date"] == new_due.isoformat()
        # 280 - 62 = 218 天 = 31 周 1 天
        assert body["gestational_age"] == {"weeks": 31, "days": 1}

        events = asyncio.run(_events(mother.family_id))
        assert len(events) == 1
        kind, actor, payload = events[0]
        assert kind == "due_date_changed" and str(actor) == mother.account_id
        assert payload == {"from": before["due_date"], "to": new_due.isoformat()}


def test_out_of_range_dates_are_rejected() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        # 预产期在 281 天后：今天还没怀上（孕周为负）
        assert _patch(client, mother, date.today() + timedelta(days=281)).status_code == 422
        # 预产期在 15 天前：已经超过 42 周
        assert _patch(client, mother, date.today() - timedelta(days=15)).status_code == 422
        # 两端都可以：正好 0 周 0 天、正好 42 周
        assert _patch(client, mother, date.today() + timedelta(days=280)).status_code == 200
        assert _patch(client, mother, date.today() - timedelta(days=14)).status_code == 200


def test_people_outside_the_family_cannot_change_it() -> None:
    with TestClient(create_app()) as client:
        mother = register(client)
        add_pregnancy(client, mother)
        stranger = register(client)
        stranger.pregnancy_id = mother.pregnancy_id
        assert _patch(client, stranger, date.today() + timedelta(days=100)).status_code == 403


def test_me_reports_the_current_family_and_pregnancy() -> None:
    with TestClient(create_app()) as client:
        mother = register(client, nickname="阿敏")
        me = client.get("/api/v1/me", headers=mother.headers).json()
        assert me == {
            "account_id": mother.account_id,
            "family_id": mother.family_id,
            "pregnancy_id": None,
            "role": "mother",
        }
        add_pregnancy(client, mother)
        me = client.get("/api/v1/me", headers=mother.headers).json()
        assert me["pregnancy_id"] == mother.pregnancy_id
