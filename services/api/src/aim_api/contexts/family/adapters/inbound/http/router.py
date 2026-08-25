from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from aim_api.contexts.family.adapters.outbound.persistence.repositories import (
    SqlAlchemyFamilyUnitOfWork,
)
from aim_api.contexts.family.application.commands import (
    accept_invitation,
    create_family,
    invite_member,
)
from aim_api.contexts.family.application.commands.accept_invitation import AcceptInvitationCommand
from aim_api.contexts.family.application.commands.create_family import CreateFamilyCommand
from aim_api.contexts.family.application.commands.invite_member import InviteMemberCommand
from aim_api.contexts.family.application.ports import PersistenceConflict
from aim_api.contexts.family.application.queries import get_family
from aim_api.contexts.family.application.queries.get_family import GetFamilyQuery
from aim_api.contexts.family.domain.errors import (
    DuplicateFamilyMember,
    FamilyAccessDenied,
    FamilyDomainError,
    InvitationExpired,
    InvitationNotFound,
    InvitationUsed,
    InviteeMismatch,
)
from aim_api.contexts.family.domain.family import Family, FamilyMemberRole
from aim_api.platform.auth.context import ActorContext, authenticate
from aim_api.platform.http.errors import ConflictError, ForbiddenError, NotFoundError

router = APIRouter(tags=["family"])


class CreateFamilyRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    role: FamilyMemberRole


class InviteMemberRequest(BaseModel):
    invitee_phone: str = Field(min_length=6, max_length=20)
    role: FamilyMemberRole


class FamilyMemberResponse(BaseModel):
    account_id: UUID
    role: FamilyMemberRole
    #: 为空时由客户端回退显示角色名。
    nickname: str | None
    status: str
    invited_at: datetime | None
    joined_at: datetime | None


class FamilyResponse(BaseModel):
    id: UUID
    name: str
    created_by: UUID
    created_at: datetime
    members: list[FamilyMemberResponse]


class InvitationResponse(BaseModel):
    invitation_id: UUID
    family_id: UUID
    role: FamilyMemberRole
    expires_at: datetime
    token: str


def _family_response(family: Family) -> FamilyResponse:
    return FamilyResponse(
        id=family.id,
        name=family.name,
        created_by=family.created_by,
        created_at=family.created_at,
        members=[
            FamilyMemberResponse(
                account_id=member.account_id,
                role=member.role,
                nickname=member.nickname,
                status=member.status.value,
                invited_at=member.invited_at,
                joined_at=member.joined_at,
            )
            for member in family.members.values()
        ],
    )


def _translate(error: Exception) -> None:
    if isinstance(error, (FamilyAccessDenied,)):
        raise ForbiddenError(str(error)) from error
    if isinstance(error, (DuplicateFamilyMember, InvitationUsed, InviteeMismatch)):
        raise ConflictError(str(error)) from error
    if isinstance(error, (InvitationExpired,)):
        raise ConflictError(str(error)) from error
    if isinstance(error, (InvitationNotFound, ValueError)):
        raise NotFoundError(str(error)) from error
    if isinstance(error, PersistenceConflict):
        raise ConflictError(str(error)) from error
    if isinstance(error, FamilyDomainError):
        raise ConflictError(str(error)) from error
    raise error


def _actor(request: Request) -> ActorContext:
    return authenticate(request)


@router.post("/api/v1/families", response_model=FamilyResponse, status_code=201)
async def create_family_endpoint(payload: CreateFamilyRequest, request: Request) -> FamilyResponse:
    actor = _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyFamilyUnitOfWork(session)
        try:
            family = await create_family.execute(
                CreateFamilyCommand(
                    account_id=actor.account_id,
                    phone=actor.phone,
                    name=payload.name,
                    role=payload.role,
                ),
                uow,
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return _family_response(family)


@router.post(
    "/api/v1/families/{family_id}/invitations",
    response_model=InvitationResponse,
    status_code=201,
)
async def invite_member_endpoint(
    family_id: UUID, payload: InviteMemberRequest, request: Request
) -> InvitationResponse:
    actor = _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyFamilyUnitOfWork(session)
        try:
            result = await invite_member.execute(
                InviteMemberCommand(
                    family_id=family_id,
                    invited_by=actor.account_id,
                    invitee_phone=payload.invitee_phone,
                    role=payload.role,
                ),
                uow,
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return InvitationResponse(
            invitation_id=result.invitation.id,
            family_id=result.invitation.family_id,
            role=result.invitation.role,
            expires_at=result.invitation.expires_at,
            token=result.token,
        )


@router.post("/api/v1/family-invitations/{token}/accept", response_model=FamilyResponse)
async def accept_invitation_endpoint(token: str, request: Request) -> FamilyResponse:
    actor = _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyFamilyUnitOfWork(session)
        try:
            family = await accept_invitation.execute(
                AcceptInvitationCommand(
                    invitation_token=token,
                    account_id=actor.account_id,
                    phone=actor.phone,
                ),
                uow,
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return _family_response(family)


@router.get("/api/v1/families/{family_id}", response_model=FamilyResponse)
async def get_family_endpoint(family_id: UUID, request: Request) -> FamilyResponse:
    actor = _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyFamilyUnitOfWork(session)
        try:
            family = await get_family.execute(
                GetFamilyQuery(family_id=family_id, account_id=actor.account_id), uow
            )
        except Exception as error:
            await uow.rollback()
            _translate(error)
        return _family_response(family)
