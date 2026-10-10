"""孕周推进时续上本周任务。"""

from __future__ import annotations

import asyncio
from datetime import date, timedelta
from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings


def _headers(account_id: str, phone: str) -> dict[str, str]:
    token = issue_session_token(UUID(account_id), phone, get_settings().auth_secret)
    return {"Authorization": f"Bearer {token}"}


def _phone(account_id: str) -> str:
    return "137" + str(int(UUID(account_id)) % 10**8).zfill(8)


def _as_of(due: date, week: int) -> date:
    """预产期前 280 天是 0 周 0 天；取该周第 1 天。"""
    return due - timedelta(days=280) + timedelta(weeks=week, days=1)


def _setup(client: TestClient, due: date) -> tuple[dict[str, str], str]:
    account_id = str(uuid4())
    headers = _headers(account_id, _phone(account_id))
    family = client.post(
        "/api/v1/families", headers=headers, json={"name": "续任务家庭", "role": "mother"}
    ).json()
    pregnancy = client.post(
        f"/api/v1/families/{family['id']}/pregnancies",
        headers=headers,
        json={"due_date": due.isoformat()},
    ).json()
    return headers, pregnancy["id"]


def _source_ids(
    client: TestClient, pregnancy_id: str, headers: dict[str, str], as_of: date
) -> list[str]:
    today = client.get(
        f"/api/v1/pregnancies/{pregnancy_id}/today?as_of={as_of.isoformat()}", headers=headers
    )
    assert today.status_code == 200, today.text
    plan = client.get(f"/api/v1/pregnancies/{pregnancy_id}/plan", headers=headers)
    assert plan.status_code == 200, plan.text
    return [task["source_id"] for task in plan.json()["tasks"] if task["source_id"]]


def test_advancing_weeks_adds_only_the_current_weeks_templates() -> None:
    due = date(2027, 1, 12)
    with TestClient(create_app()) as client:
        headers, pregnancy_id = _setup(client, due)
        created = client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/plan",
            headers=headers,
            json={"as_of": _as_of(due, 6).isoformat()},
        )
        assert created.status_code == 201, created.text
        before = {task["source_id"] for task in created.json()["tasks"]}

        first = _source_ids(client, pregnancy_id, headers, _as_of(due, 25))
        second = _source_ids(client, pregnancy_id, headers, _as_of(due, 25))

    added = set(first) - before
    assert added and all(source_id.startswith("w25-") for source_id in added)
    assert not any(source_id.startswith(("w13-", "w20-")) for source_id in first), "跳过的孕周不补"
    assert sorted(first) == sorted(second), "再次读取不重复生成"


def test_deleted_template_tasks_do_not_come_back() -> None:
    due = date(2027, 1, 12)
    with TestClient(create_app()) as client:
        headers, pregnancy_id = _setup(client, due)
        client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/plan",
            headers=headers,
            json={"as_of": _as_of(due, 6).isoformat()},
        )
        _source_ids(client, pregnancy_id, headers, _as_of(due, 25))
        plan = client.get(f"/api/v1/pregnancies/{pregnancy_id}/plan", headers=headers).json()
        victim = next(
            task for task in plan["tasks"] if (task["source_id"] or "").startswith("w25-")
        )
        deleted = client.delete(
            f"/api/v1/pregnancies/{pregnancy_id}/tasks/{victim['id']}", headers=headers
        )
        assert deleted.status_code == 204, deleted.text

        after = _source_ids(client, pregnancy_id, headers, _as_of(due, 26))

    assert victim["source_id"] not in after


def test_without_a_plan_today_behaves_as_before() -> None:
    due = date(2027, 1, 12)
    with TestClient(create_app()) as client:
        headers, pregnancy_id = _setup(client, due)
        today = client.get(
            f"/api/v1/pregnancies/{pregnancy_id}/today?as_of={_as_of(due, 25).isoformat()}",
            headers=headers,
        )
    # 没有计划时维持现有行为（以实现前的返回码为准，通常为 404），关键是不能 500。
    assert today.status_code < 500, today.text


def test_get_plan_syncs_with_todays_week() -> None:
    # 让「今天」落在第 26 周：GET /plan 不接受 as_of，只能按服务器今天算。
    due = date.today() + timedelta(weeks=14)
    with TestClient(create_app()) as client:
        headers, pregnancy_id = _setup(client, due)
        client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/plan",
            headers=headers,
            json={"as_of": _as_of(due, 6).isoformat()},
        )
        plan = client.get(f"/api/v1/pregnancies/{pregnancy_id}/plan", headers=headers)

    assert plan.status_code == 200, plan.text
    assert any((task["source_id"] or "").startswith("w25-") for task in plan.json()["tasks"])


def test_concurrent_syncs_create_each_template_once() -> None:
    from aim_api.contexts.planning.adapters.outbound.persistence.repositories import (
        SqlAlchemyPlanningUnitOfWork,
    )
    from aim_api.contexts.planning.application.commands import sync_week_tasks

    due = date(2027, 1, 12)
    with TestClient(create_app()) as client:
        headers, pregnancy_id = _setup(client, due)
        client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/plan",
            headers=headers,
            json={"as_of": _as_of(due, 6).isoformat()},
        )
        database = client.app.state.database

        async def one_sync() -> int:
            async with database.session() as session:
                uow = SqlAlchemyPlanningUnitOfWork(session)
                return await sync_week_tasks.execute(
                    sync_week_tasks.SyncWeekTasksCommand(
                        pregnancy_id=UUID(pregnancy_id), as_of=_as_of(due, 25)
                    ),
                    uow,
                )

        async def both() -> list[int]:
            return list(await asyncio.gather(one_sync(), one_sync()))

        created = client.portal.call(both) if hasattr(client, "portal") else asyncio.run(both())
        plan = client.get(f"/api/v1/pregnancies/{pregnancy_id}/plan", headers=headers).json()

    w25 = [
        task["source_id"] for task in plan["tasks"] if (task["source_id"] or "").startswith("w25-")
    ]
    assert len(w25) == len(set(w25)), "每个模板只对应一个任务"
    assert sum(created) == len(w25)


def _w25_task_count(client: TestClient, pregnancy_id: str) -> int:
    from sqlalchemy import text

    database = client.app.state.database

    async def count() -> int:
        async with database.session() as session:
            return await session.scalar(
                text(
                    "SELECT count(*) FROM tasks WHERE pregnancy_id = :p AND source_id LIKE 'w25-%'"
                ),
                {"p": UUID(pregnancy_id)},
            )

    return client.portal.call(count)


def test_non_member_reads_do_not_trigger_sync() -> None:
    due = date.today() + timedelta(weeks=14)
    with TestClient(create_app()) as client:
        headers, pregnancy_id = _setup(client, due)
        client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/plan",
            headers=headers,
            json={"as_of": _as_of(due, 6).isoformat()},
        )
        stranger_id = str(uuid4())
        stranger = _headers(stranger_id, _phone(stranger_id))
        today = client.get(f"/api/v1/pregnancies/{pregnancy_id}/today", headers=stranger)
        plan = client.get(f"/api/v1/pregnancies/{pregnancy_id}/plan", headers=stranger)
        after_stranger = _w25_task_count(client, pregnancy_id)
        client.get(f"/api/v1/pregnancies/{pregnancy_id}/plan", headers=headers)
        after_member = _w25_task_count(client, pregnancy_id)

    assert today.status_code == 403, today.text
    assert plan.status_code == 403, plan.text
    assert after_stranger == 0, "非家庭成员的读取不能写库"
    assert after_member > 0


def test_sync_failure_does_not_break_reads(monkeypatch) -> None:
    from aim_api.contexts.planning.application.commands import sync_week_tasks

    async def boom(*args, **kwargs):
        raise RuntimeError("sync exploded")

    monkeypatch.setattr(sync_week_tasks, "execute", boom)
    due = date.today() + timedelta(weeks=14)
    with TestClient(create_app()) as client:
        headers, pregnancy_id = _setup(client, due)
        client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/plan",
            headers=headers,
            json={"as_of": _as_of(due, 6).isoformat()},
        )
        today = client.get(f"/api/v1/pregnancies/{pregnancy_id}/today", headers=headers)
        plan = client.get(f"/api/v1/pregnancies/{pregnancy_id}/plan", headers=headers)

    assert today.status_code == 200, today.text
    assert plan.status_code == 200, plan.text


def test_agent_list_tasks_syncs_with_todays_week() -> None:
    due = date.today() + timedelta(weeks=14)
    account_id = str(uuid4())
    headers = _headers(account_id, _phone(account_id))
    with TestClient(create_app()) as client:
        family = client.post(
            "/api/v1/families", headers=headers, json={"name": "续任务家庭", "role": "mother"}
        ).json()
        pregnancy_id = client.post(
            f"/api/v1/families/{family['id']}/pregnancies",
            headers=headers,
            json={"due_date": due.isoformat()},
        ).json()["id"]
        created = client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/plan",
            headers=headers,
            json={"as_of": _as_of(due, 6).isoformat()},
        ).json()
        listed = client.post(
            "/internal/agent-tools/list-tasks",
            headers={
                "Service-Authorization": f"Bearer {get_settings().agent_service_secret}",
                "Actor-Account-Id": account_id,
                "Family-Id": family["id"],
                "Pregnancy-Id": pregnancy_id,
                "Eve-Session-Id": f"eve-sync-{account_id}",
                "Idempotency-Key": "list-1",
            },
            json={},
        )
        w25 = _w25_task_count(client, pregnancy_id)

    assert listed.status_code == 200, listed.text
    assert w25 > 0
    assert len(listed.json()["data"]["tasks"]) == len(created["tasks"]) + w25


def test_migration_backfills_seeds_for_existing_template_tasks() -> None:
    """上线前生成的计划没有种子；回填后它们的模板任务都算「生成过」。"""
    import os
    from pathlib import Path

    from alembic import command
    from alembic.config import Config
    from sqlalchemy import text

    api_root = str(Path(__file__).resolve().parents[3])
    config = Config(os.path.join(api_root, "alembic.ini"))
    config.set_main_option("script_location", os.path.join(api_root, "migrations"))

    due = date(2027, 1, 12)
    with TestClient(create_app()) as client:
        headers, pregnancy_id = _setup(client, due)
        created = client.post(
            f"/api/v1/pregnancies/{pregnancy_id}/plan",
            headers=headers,
            json={"as_of": _as_of(due, 6).isoformat()},
        ).json()

    command.downgrade(config, "0011_family_events")
    command.upgrade(config, "head")

    with TestClient(create_app()) as client:
        database = client.app.state.database

        async def seeds() -> set[str]:
            async with database.session() as session:
                rows = await session.scalars(
                    text("SELECT template_id FROM plan_template_seeds WHERE plan_id = :p"),
                    {"p": UUID(created["id"])},
                )
                return set(rows.all())

        seeded = client.portal.call(seeds)

    assert seeded == {task["source_id"] for task in created["tasks"]}
    assert seeded
