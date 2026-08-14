from __future__ import annotations

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


def test_stale_task_version_returns_409() -> None:
    account_id = str(uuid4())
    phone = _phone(account_id)
    with TestClient(create_app()) as client:
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

        async def seed():
            seed_db = create_database(get_settings().database_url)
            try:
                async with seed_db.session() as session:
                    uow = SqlAlchemyPlanningUnitOfWork(session)
                    return await generate_initial_plan(
                        GenerateInitialPlanCommand(
                            pregnancy_id=UUID(pregnancy["id"]),
                            family_id=UUID(family["id"]),
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
                        uow,
                    )
            finally:
                await seed_db.dispose()

        import asyncio

        plan = asyncio.run(seed())
        task_id = str(plan.tasks[0].id)
        first = client.post(
            f"/api/v1/tasks/{task_id}/complete",
            headers=_headers(account_id, phone),
            json={"expected_version": 1},
        )
        assert first.status_code == 200, first.text
        stale = client.post(
            f"/api/v1/tasks/{task_id}/complete",
            headers=_headers(account_id, phone),
            json={"expected_version": 1},
        )
        assert stale.status_code == 409
