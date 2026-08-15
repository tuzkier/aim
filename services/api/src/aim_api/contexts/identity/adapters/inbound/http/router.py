from __future__ import annotations

from datetime import date
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field

from aim_api.contexts.family.adapters.outbound.persistence.repositories import (
    SqlAlchemyFamilyUnitOfWork,
)
from aim_api.contexts.family.application.commands import create_family
from aim_api.contexts.family.application.commands.create_family import CreateFamilyCommand
from aim_api.contexts.family.domain.family import FamilyMemberRole
from aim_api.contexts.pregnancy.adapters.outbound.persistence.repositories import (
    SqlAlchemyPregnancyUnitOfWork,
)
from aim_api.contexts.pregnancy.application.commands import create_pregnancy
from aim_api.contexts.pregnancy.application.commands.create_pregnancy import (
    CreatePregnancyCommand,
)
from aim_api.platform.auth.context import issue_session_token
from aim_api.platform.config.settings import Settings
from aim_api.platform.database.session import Database

router = APIRouter(tags=["identity"])


class DemoSessionRequest(BaseModel):
    phone: str = Field(min_length=6, max_length=20)
    due_date: date | None = None


class DemoSessionResponse(BaseModel):
    account_id: UUID
    phone: str
    family_id: UUID
    pregnancy_id: UUID | None
    role: FamilyMemberRole
    token: str


async def _ensure_family_and_pregnancy(
    payload: DemoSessionRequest,
    account_id: UUID,
    database: Database,
) -> tuple[UUID, UUID | None, bool]:
    created = False
    async with database.session() as session:
        family_uow = SqlAlchemyFamilyUnitOfWork(session)
        family = await family_uow.repository.get_first_family_for_account(account_id)
        if family is None:
            family = await create_family.execute(
                CreateFamilyCommand(
                    account_id=account_id,
                    phone=payload.phone,
                    name="我的家庭",
                    role=FamilyMemberRole.mother,
                ),
                family_uow,
            )
            created = True

        pregnancy = None
        if payload.due_date is not None:
            pregnancy_uow = SqlAlchemyPregnancyUnitOfWork(session)
            pregnancy = await pregnancy_uow.repository.get_first_pregnancy_for_family(family.id)
            if pregnancy is None:
                pregnancy = await create_pregnancy.execute(
                    CreatePregnancyCommand(
                        family_id=family.id,
                        account_id=account_id,
                        due_date=payload.due_date,
                    ),
                    pregnancy_uow,
                )
                created = True
        else:
            pregnancy_uow = SqlAlchemyPregnancyUnitOfWork(session)
            pregnancy = await pregnancy_uow.repository.get_first_pregnancy_for_family(family.id)

        return family.id, pregnancy.id if pregnancy is not None else None, created


@router.post(
    "/api/v1/auth/demo-session",
    response_model=DemoSessionResponse,
    status_code=200,
    responses={200: {"model": DemoSessionResponse}, 201: {"model": DemoSessionResponse}},
)
async def create_demo_session(
    payload: DemoSessionRequest,
    request: Request,
    response: Response,
) -> DemoSessionResponse:
    settings: Settings = request.app.state.settings
    if not settings.dev_auth_enabled:
        raise HTTPException(status_code=404, detail="Not Found")

    database: Database = request.app.state.database
    async with database.session() as session:
        family_uow = SqlAlchemyFamilyUnitOfWork(session)
        account = await family_uow.repository.get_account_by_phone(payload.phone)

    account_id = account.id if account is not None else uuid4()
    family_id, pregnancy_id, created = await _ensure_family_and_pregnancy(
        payload,
        account_id,
        database,
    )

    body = DemoSessionResponse(
        account_id=account_id,
        phone=payload.phone,
        family_id=family_id,
        pregnancy_id=pregnancy_id,
        role=FamilyMemberRole.mother,
        token=issue_session_token(account_id, payload.phone, settings.auth_secret),
    )
    response.status_code = 201 if created else 200
    return body
