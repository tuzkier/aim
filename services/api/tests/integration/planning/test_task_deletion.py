from __future__ import annotations

import asyncio
from datetime import UTC, datetime
from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.contexts.planning.adapters.outbound.persistence.repositories import (
    SqlAlchemyPlanningUnitOfWork,
)
from aim_api.contexts.planning.application.commands.generate_initial_plan import (
    GenerateInitialPlanCommand,
    TaskSeed,
)
from aim_api.contexts.planning.application.commands.generate_initial_plan import (
    execute as generate_initial_plan,
)
from aim_api.contexts.planning.domain.task import ActorType, TaskSourceType
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import get_settings
from aim_api.platform.database.session import create_database


def _headers(account_id: str, phone: str) -> dict[str, str]:
    token = issue_session_token(UUID(account_id), phone, get_settings().auth_secret)
    return {"Authorization": f"Bearer {token}"}


def _phone(account_id: str) -> str:
    return "138" + str(int(UUID(account_id)) % 10**8).zfill(8)


def _seed_task(pregnancy_id: str, family_id: str, account_id: str) -> str:
    async def seed():
        database = create_database(get_settings().database_url)
        try:
            async with database.session() as session:
                plan = await generate_initial_plan(
                    GenerateInitialPlanCommand(
                        pregnancy_id=UUID(pregnancy_id),
                        family_id=UUID(family_id),
                        account_id=UUID(account_id),
                        tasks=(
                            TaskSeed(
                                title="预约系统超声",
                                source_type=TaskSourceType.template,
                                source_id="week-18-ultrasound",
                                changed_by_actor_type=ActorType.account,
                                changed_by_actor_id=UUID(account_id),
                            ),
                        ),
                        now=datetime(2026, 8, 14, tzinfo=UTC),
                    ),
                    SqlAlchemyPlanningUnitOfWork(session),
                )
                return str(plan.tasks[0].id)
        finally:
            await database.dispose()

    return asyncio.run(seed())


def _make_pregnancy(client: TestClient, account_id: str, phone: str) -> tuple[str, str]:
    family = client.post(
        "/api/v1/families",
        headers=_headers(account_id, phone),
        json={"name": "计划家庭", "role": "mother"},
    ).json()
    pregnancy = client.post(
        f"/api/v1/families/{family['id']}/pregnancies",
        headers=_headers(account_id, phone),
        json={"due_date": "2026-09-25"},
    ).json()
    return family["id"], pregnancy["id"]


def test_task_can_be_deleted_and_disappears_from_the_plan() -> None:
    """删除是「撤销 Agent 新建待办」的落地路径，见
    docs/superpowers/specs/2026-08-21-agent-create-tools-design.md。"""
    account_id = str(uuid4())
    phone = _phone(account_id)
    with TestClient(create_app()) as client:
        family_id, pregnancy_id = _make_pregnancy(client, account_id, phone)
        task_id = _seed_task(pregnancy_id, family_id, account_id)

        deleted = client.delete(
            f"/api/v1/pregnancies/{pregnancy_id}/tasks/{task_id}",
            headers=_headers(account_id, phone),
        )
        assert deleted.status_code == 204, deleted.text

        plan = client.get(
            f"/api/v1/pregnancies/{pregnancy_id}/plan",
            headers=_headers(account_id, phone),
        ).json()
        assert all(task["id"] != task_id for task in plan["tasks"])


def test_deleting_a_missing_task_is_idempotent() -> None:
    """撤销可能被重放（toast 连点、网络重试），重复删除不该报错。"""
    account_id = str(uuid4())
    phone = _phone(account_id)
    with TestClient(create_app()) as client:
        _, pregnancy_id = _make_pregnancy(client, account_id, phone)

        response = client.delete(
            f"/api/v1/pregnancies/{pregnancy_id}/tasks/{uuid4()}",
            headers=_headers(account_id, phone),
        )
        assert response.status_code == 204, response.text


def test_task_cannot_be_deleted_from_another_family() -> None:
    owner_id = str(uuid4())
    owner_phone = _phone(owner_id)
    outsider_id = str(uuid4())
    outsider_phone = _phone(outsider_id)
    with TestClient(create_app()) as client:
        family_id, pregnancy_id = _make_pregnancy(client, owner_id, owner_phone)
        task_id = _seed_task(pregnancy_id, family_id, owner_id)

        response = client.delete(
            f"/api/v1/pregnancies/{pregnancy_id}/tasks/{task_id}",
            headers=_headers(outsider_id, outsider_phone),
        )
        assert response.status_code == 403, response.text

        plan = client.get(
            f"/api/v1/pregnancies/{pregnancy_id}/plan",
            headers=_headers(owner_id, owner_phone),
        ).json()
        assert any(task["id"] == task_id for task in plan["tasks"])
