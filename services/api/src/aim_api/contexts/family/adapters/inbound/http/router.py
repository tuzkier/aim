from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, Request
from pydantic import BaseModel, field_validator, Field

from aim_api.contexts.family.adapters.outbound.persistence.repositories import (
    SqlAlchemyFamilyUnitOfWork,
)
from aim_api.contexts.family.application.commands import (
    create_family,
    invite_member,
)
from aim_api.contexts.family.application.commands.create_family import CreateFamilyCommand
from aim_api.contexts.family.application.commands.invite_member import InviteMemberCommand
from aim_api.contexts.family.application.ports import PersistenceConflict
from aim_api.contexts.family.application.queries import get_family
from aim_api.contexts.family.application.queries.get_family import GetFamilyQuery
from aim_api.contexts.family.domain.errors import (
    FamilyNotFound,
    DuplicateFamilyMember,
    FamilyAccessDenied,
    FamilyDomainError,
    InvitationExpired,
    InvitationNotFound,
    InvitationUsed,
    InviteeMismatch,
)
from aim_api.contexts.family.domain.family import Family, FamilyMemberRole
from aim_api.platform.auth.context import ActorContext, authenticate_active
from aim_api.platform.http.errors import ConflictError, ForbiddenError, NotFoundError

router = APIRouter(tags=["family"])


class CreateFamilyRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    role: FamilyMemberRole


class InviteMemberRequest(BaseModel):
    invitee_phone: str = Field(min_length=6, max_length=20)
    role: FamilyMemberRole


class RenameFamilyRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)

    @field_validator("name")
    @classmethod
    def _not_blank(cls, value: str) -> str:
        # 纯空格能通过 min_length，但一个看不见名字的家庭对用户毫无意义。
        stripped = value.strip()
        if not stripped:
            raise ValueError("家庭名不能为空")
        return stripped


class UpdateMyMembershipRequest(BaseModel):
    #: 两项都可选，只传要改的那个。None 表示「这次不改」，不是「清空」。
    nickname: str | None = Field(default=None, max_length=60)
    role: FamilyMemberRole | None = None


class FamilyMemberResponse(BaseModel):
    account_id: UUID
    role: FamilyMemberRole
    #: 为空时由客户端回退显示角色名。
    nickname: str | None
    status: str
    invited_at: datetime | None
    joined_at: datetime | None
    #: 管理员 = 家庭创建人，只有他能移出别人。
    is_admin: bool = False


class FamilyInvitationResponse(BaseModel):
    id: UUID
    #: 打码后的手机号，如 138****5678。
    phone_masked: str
    role: FamilyMemberRole
    invited_by: UUID
    expires_at: datetime
    #: pending / declined / expired
    status: str


class FamilyResponse(BaseModel):
    id: UUID
    name: str
    created_by: UUID
    created_at: datetime
    members: list[FamilyMemberResponse]
    #: 还没处理完的邀请（含过期 7 天内的），只在读取家庭时给出。
    invitations: list[FamilyInvitationResponse] = []


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
                is_admin=member.account_id == family.created_by,
            )
            for member in family.members.values()
        ],
    )


def mask_phone(phone: str) -> str:
    return f"{phone[:3]}****{phone[-4:]}" if len(phone) >= 7 else phone


def _invitation_responses(invitations, now: datetime) -> list[FamilyInvitationResponse]:
    """待处理与暂不的邀请照列；过期的再列 7 天，方便一键重发。"""
    result = []
    for invitation in invitations:
        if invitation.status.value not in ("pending", "declined", "expired"):
            continue
        expired = now >= invitation.expires_at or invitation.status.value == "expired"
        if expired and now - invitation.expires_at > timedelta(days=7):
            continue
        result.append(
            FamilyInvitationResponse(
                id=invitation.id,
                phone_masked=mask_phone(invitation.invitee_phone),
                role=invitation.role,
                invited_by=invitation.invited_by,
                expires_at=invitation.expires_at,
                status="expired" if expired else invitation.status.value,
            )
        )
    return result


def _translate(error: Exception) -> None:
    if isinstance(error, (FamilyAccessDenied,)):
        raise ForbiddenError(str(error)) from error
    if isinstance(error, (DuplicateFamilyMember, InvitationUsed, InviteeMismatch)):
        raise ConflictError(str(error)) from error
    if isinstance(error, (InvitationExpired,)):
        raise ConflictError(str(error)) from error
    if isinstance(error, (FamilyNotFound, InvitationNotFound, ValueError)):
        raise NotFoundError(str(error)) from error
    if isinstance(error, PersistenceConflict):
        raise ConflictError(str(error)) from error
    if isinstance(error, FamilyDomainError):
        raise ConflictError(str(error)) from error
    raise error


async def _actor(request: Request) -> ActorContext:
    return await authenticate_active(request)


@router.post("/api/v1/families", response_model=FamilyResponse, status_code=201)
async def create_family_endpoint(payload: CreateFamilyRequest, request: Request) -> FamilyResponse:
    actor = await _actor(request)
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
    actor = await _actor(request)
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


@router.get("/api/v1/families/{family_id}", response_model=FamilyResponse)
async def get_family_endpoint(family_id: UUID, request: Request) -> FamilyResponse:
    actor = await _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyFamilyUnitOfWork(session)
        try:
            family = await get_family.execute(
                GetFamilyQuery(family_id=family_id, account_id=actor.account_id), uow
            )
            invitations = await uow.repository.list_invitations_for_family(family_id)
        except Exception as error:
            await uow.rollback()
            _translate(error)
        response = _family_response(family)
        response.invitations = _invitation_responses(invitations, datetime.now(UTC))
        return response


@router.patch("/api/v1/families/{family_id}", response_model=FamilyResponse)
async def rename_family_endpoint(
    family_id: UUID, payload: RenameFamilyRequest, request: Request
) -> FamilyResponse:
    actor = await _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyFamilyUnitOfWork(session)
        try:
            if not await uow.repository.is_active_member(family_id, actor.account_id):
                raise FamilyAccessDenied(str(family_id))
            await uow.repository.rename_family(family_id, payload.name)
            await uow.commit()
            family = await uow.repository.get_family(family_id)
        except Exception as error:
            await uow.rollback()
            _translate(error)
        if family is None:
            raise NotFoundError(str(family_id))
        return _family_response(family)


@router.patch("/api/v1/families/{family_id}/members/me", response_model=FamilyResponse)
async def update_my_membership_endpoint(
    family_id: UUID, payload: UpdateMyMembershipRequest, request: Request
) -> FamilyResponse:
    """改自己的称呼和角色。

    端点里没有 member_id 入口——改别人需要一套「谁能改谁」的权限模型，
    而当前没有需求支撑它。想改别人时，加的应当是那套模型，不是这个参数。
    """
    actor = await _actor(request)
    database = request.app.state.database
    async with database.session() as session:
        uow = SqlAlchemyFamilyUnitOfWork(session)
        try:
            if not await uow.repository.is_active_member(family_id, actor.account_id):
                raise FamilyAccessDenied(str(family_id))
            await uow.repository.update_member_profile(
                family_id,
                actor.account_id,
                nickname=payload.nickname,
                role=payload.role,
            )
            await uow.commit()
            family = await uow.repository.get_family(family_id)
        except Exception as error:
            await uow.rollback()
            _translate(error)
        if family is None:
            raise NotFoundError(str(family_id))
        return _family_response(family)
