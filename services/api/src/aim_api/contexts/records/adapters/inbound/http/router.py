from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from aim_api.contexts.family.application.ports import PersistenceConflict
from aim_api.contexts.records.adapters.outbound.persistence.repositories import (
    SqlAlchemyRecordsUnitOfWork,
)
from aim_api.contexts.records.application.commands import create_record, delete_record, update_record
from aim_api.contexts.records.application.commands.create_record import CreateRecordCommand
from aim_api.contexts.records.application.commands.delete_record import DeleteRecordCommand
from aim_api.contexts.records.application.commands.update_record import UpdateRecordCommand
from aim_api.contexts.records.application.queries import get_record, list_records
from aim_api.contexts.records.application.queries.get_record import GetRecordQuery
from aim_api.contexts.records.application.queries.list_records import ListRecordsQuery
from aim_api.contexts.records.domain.errors import (
    RecordAccessDenied,
    RecordNotFound,
    RecordsDomainError,
)
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility
from aim_api.platform.auth.context import ActorContext, authenticate_active
from aim_api.platform.http.errors import ConflictError, ForbiddenError, NotFoundError

router = APIRouter(tags=["records"])


class CreateRecordRequest(BaseModel):
    type: RecordType
    occurred_at: datetime
    visibility: RecordVisibility
    title: str | None = Field(default=None, max_length=200)
    content: str | None = Field(default=None, max_length=5000)
    structured_data: dict[str, Any]
    #: 先经 /attachments 上传拿到的图片编号。必须属于同一家庭、尚未挂到别的记录。
    attachment_ids: list[UUID] = Field(default_factory=list, max_length=4)


class UpdateRecordRequest(BaseModel):
    occurred_at: datetime | None = None
    visibility: RecordVisibility | None = None
    title: str | None = Field(default=None, max_length=200)
    content: str | None = Field(default=None, max_length=5000)
    structured_data: dict[str, Any] | None = None


class RecordResponse(BaseModel):
    id: UUID
    pregnancy_id: UUID
    family_id: UUID
    author_account_id: UUID
    type: RecordType
    occurred_at: datetime
    visibility: RecordVisibility
    title: str | None
    content: str | None
    structured_data: dict[str, Any]
    attachment_refs: list[str]
    created_at: datetime
    updated_at: datetime


class RecordListResponse(BaseModel):
    records: list[RecordResponse]


def _response(record: Record) -> RecordResponse:
    return RecordResponse(
        id=record.id,
        pregnancy_id=record.pregnancy_id,
        family_id=record.family_id,
        author_account_id=record.author_account_id,
        type=record.record_type,
        occurred_at=record.occurred_at,
        visibility=record.visibility,
        title=record.title,
        content=record.content,
        structured_data=record.structured_data,
        attachment_refs=record.attachment_refs,
        created_at=record.created_at,
        updated_at=record.updated_at,
    )


def _translate(error: Exception) -> None:
    if isinstance(error, RecordAccessDenied):
        raise ForbiddenError(str(error)) from error
    if isinstance(error, RecordNotFound):
        raise NotFoundError(str(error)) from error
    if isinstance(error, PersistenceConflict):
        raise ConflictError(str(error)) from error
    if isinstance(error, RecordsDomainError):
        raise ConflictError(str(error)) from error
    raise error


async def _actor(request: Request) -> ActorContext:
    return await authenticate_active(request)


async def _family_id_for_pregnancy(pregnancy_id: UUID, uow) -> UUID:
    pregnancy = await uow.pregnancy_ownership.get_pregnancy(pregnancy_id)
    if pregnancy is None:
        raise RecordNotFound("pregnancy does not exist")
    return pregnancy.family_id


@router.post(
    "/api/v1/pregnancies/{pregnancy_id}/records",
    response_model=RecordResponse,
    status_code=201,
)
async def create_record_endpoint(
    pregnancy_id: UUID, payload: CreateRecordRequest, request: Request
) -> RecordResponse:
    actor = await _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyRecordsUnitOfWork(session)
        try:
            family_id = await _family_id_for_pregnancy(pregnancy_id, uow)
            record = await create_record.execute(
                CreateRecordCommand(
                    pregnancy_id=pregnancy_id,
                    family_id=family_id,
                    account_id=actor.account_id,
                    record_type=payload.type,
                    occurred_at=payload.occurred_at,
                    visibility=payload.visibility,
                    title=payload.title,
                    content=payload.content,
                    structured_data=payload.structured_data,
                    attachment_ids=tuple(payload.attachment_ids),
                ),
                uow,
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return _response(record)


@router.get(
    "/api/v1/pregnancies/{pregnancy_id}/records", response_model=RecordListResponse
)
async def list_records_endpoint(
    pregnancy_id: UUID, request: Request, type: RecordType | None = None
) -> RecordListResponse:
    actor = await _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyRecordsUnitOfWork(session)
        try:
            family_id = await _family_id_for_pregnancy(pregnancy_id, uow)
            records = await list_records.execute(
                ListRecordsQuery(
                    family_id=family_id,
                    account_id=actor.account_id,
                    pregnancy_id=pregnancy_id,
                    record_type=type,
                ),
                uow,
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return RecordListResponse(records=[_response(record) for record in records])


@router.get(
    "/api/v1/pregnancies/{pregnancy_id}/records/{record_id}", response_model=RecordResponse
)
async def get_record_endpoint(
    pregnancy_id: UUID, record_id: UUID, request: Request
) -> RecordResponse:
    actor = await _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyRecordsUnitOfWork(session)
        try:
            family_id = await _family_id_for_pregnancy(pregnancy_id, uow)
            record = await get_record.execute(
                GetRecordQuery(
                    record_id=record_id,
                    family_id=family_id,
                    account_id=actor.account_id,
                    pregnancy_id=pregnancy_id,
                ),
                uow,
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return _response(record)


@router.patch(
    "/api/v1/pregnancies/{pregnancy_id}/records/{record_id}", response_model=RecordResponse
)
async def update_record_endpoint(
    pregnancy_id: UUID, record_id: UUID, payload: UpdateRecordRequest, request: Request
) -> RecordResponse:
    actor = await _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyRecordsUnitOfWork(session)
        try:
            family_id = await _family_id_for_pregnancy(pregnancy_id, uow)
            record = await update_record.execute(
                UpdateRecordCommand(
                    record_id=record_id,
                    pregnancy_id=pregnancy_id,
                    family_id=family_id,
                    account_id=actor.account_id,
                    changes=payload.model_dump(include=payload.model_fields_set),
                ),
                uow,
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return _response(record)


@router.delete("/api/v1/pregnancies/{pregnancy_id}/records/{record_id}", status_code=204)
async def delete_record_endpoint(pregnancy_id: UUID, record_id: UUID, request: Request) -> None:
    actor = await _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyRecordsUnitOfWork(session)
        try:
            family_id = await _family_id_for_pregnancy(pregnancy_id, uow)
            await delete_record.execute(
                DeleteRecordCommand(
                    record_id=record_id,
                    pregnancy_id=pregnancy_id,
                    family_id=family_id,
                    account_id=actor.account_id,
                ),
                uow,
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
