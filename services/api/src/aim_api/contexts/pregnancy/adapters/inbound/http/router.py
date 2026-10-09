from __future__ import annotations

from datetime import date, datetime
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field, model_validator

from aim_api.contexts.pregnancy.adapters.outbound.persistence.repositories import (
    SqlAlchemyPregnancyUnitOfWork,
)
from aim_api.contexts.pregnancy.application.commands import create_pregnancy, record_fact
from aim_api.contexts.pregnancy.application.commands.create_pregnancy import CreatePregnancyCommand
from aim_api.contexts.pregnancy.application.commands.record_fact import RecordFactCommand
from aim_api.contexts.pregnancy.application.queries import get_pregnancy
from aim_api.contexts.pregnancy.application.queries.get_pregnancy import GetPregnancyQuery
from aim_api.contexts.pregnancy.domain.errors import (
    PregnancyAccessDenied,
    PregnancyDomainError,
    PregnancyNotFound,
)
from aim_api.contexts.pregnancy.domain.fact import FactSource, PregnancyFact
from aim_api.contexts.pregnancy.domain.pregnancy import Pregnancy
from aim_api.contexts.pregnancy.domain.pregnancy_dates import (
    due_date_from_last_menstrual_period,
    last_menstrual_period_from_due_date,
)
from aim_api.platform.auth.context import ActorContext, authenticate_active
from aim_api.platform.http.errors import ConflictError, ForbiddenError, NotFoundError

router = APIRouter(tags=["pregnancy"])


class CreatePregnancyRequest(BaseModel):
    due_date: date | None = None
    last_menstrual_period: date | None = None

    @model_validator(mode="after")
    def validate_date_input(self) -> CreatePregnancyRequest:
        if (self.due_date is None) == (self.last_menstrual_period is None):
            raise ValueError("provide exactly one of due_date or last_menstrual_period")
        return self

    def canonical_due_date(self) -> date:
        if self.due_date is not None:
            return self.due_date
        assert self.last_menstrual_period is not None
        return due_date_from_last_menstrual_period(self.last_menstrual_period)


class RecordFactRequest(BaseModel):
    key: str = Field(min_length=1, max_length=120)
    value: Any
    source: FactSource
    observed_at: datetime | None = None


class GestationalAgeResponse(BaseModel):
    weeks: int
    days: int


class FactResponse(BaseModel):
    id: UUID
    key: str
    value: Any
    source: FactSource
    priority: int
    status: str
    observed_at: datetime
    recorded_at: datetime


class PregnancyResponse(BaseModel):
    id: UUID
    family_id: UUID
    due_date: date
    last_menstrual_period: date
    status: str
    created_by: UUID
    created_at: datetime
    updated_at: datetime
    gestational_age: GestationalAgeResponse
    facts: list[FactResponse]


def _response(pregnancy: Pregnancy) -> PregnancyResponse:
    age = pregnancy.gestational_age()
    return PregnancyResponse(
        id=pregnancy.id,
        family_id=pregnancy.family_id,
        due_date=pregnancy.due_date,
        last_menstrual_period=last_menstrual_period_from_due_date(pregnancy.due_date),
        status=pregnancy.status.value,
        created_by=pregnancy.created_by,
        created_at=pregnancy.created_at,
        updated_at=pregnancy.updated_at,
        gestational_age=GestationalAgeResponse(weeks=age.weeks, days=age.days),
        facts=[_fact_response(fact) for fact in pregnancy.facts.all()],
    )


def _fact_response(fact: PregnancyFact) -> FactResponse:
    return FactResponse(
        id=fact.id,
        key=fact.key,
        value=fact.value,
        source=fact.source,
        priority=fact.priority,
        status=fact.status.value,
        observed_at=fact.observed_at,
        recorded_at=fact.recorded_at,
    )


def _translate(error: Exception) -> None:
    if isinstance(error, PregnancyAccessDenied):
        raise ForbiddenError(str(error)) from error
    if isinstance(error, PregnancyNotFound):
        raise NotFoundError(str(error)) from error
    if isinstance(error, PregnancyDomainError):
        raise ConflictError(str(error)) from error
    raise error


async def _actor(request: Request) -> ActorContext:
    return await authenticate_active(request)


@router.post(
    "/api/v1/families/{family_id}/pregnancies",
    response_model=PregnancyResponse,
    status_code=201,
)
async def create_pregnancy_endpoint(
    family_id: UUID, payload: CreatePregnancyRequest, request: Request
) -> PregnancyResponse:
    actor = await _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyPregnancyUnitOfWork(session)
        try:
            pregnancy = await create_pregnancy.execute(
                CreatePregnancyCommand(
                    family_id=family_id,
                    account_id=actor.account_id,
                    due_date=payload.canonical_due_date(),
                ),
                uow,
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return _response(pregnancy)


@router.get("/api/v1/pregnancies/{pregnancy_id}", response_model=PregnancyResponse)
async def get_pregnancy_endpoint(pregnancy_id: UUID, request: Request) -> PregnancyResponse:
    actor = await _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyPregnancyUnitOfWork(session)
        try:
            pregnancy = await get_pregnancy.execute(
                GetPregnancyQuery(pregnancy_id=pregnancy_id, account_id=actor.account_id), uow
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return _response(pregnancy)


@router.post(
    "/api/v1/pregnancies/{pregnancy_id}/facts",
    response_model=FactResponse,
    status_code=201,
)
async def record_fact_endpoint(
    pregnancy_id: UUID, payload: RecordFactRequest, request: Request
) -> FactResponse:
    actor = await _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyPregnancyUnitOfWork(session)
        try:
            result = await record_fact.execute(
                RecordFactCommand(
                    pregnancy_id=pregnancy_id,
                    account_id=actor.account_id,
                    key=payload.key,
                    value=payload.value,
                    source=payload.source,
                    observed_at=payload.observed_at,
                ),
                uow,
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return _fact_response(result.fact)
