"""跨模块的家庭接口：改预产期、我是谁、邀请、离开家庭、成员详情、家庭动态。

这些操作同时碰家庭、孕期、待办、记录几张表，放在组合层，和 today 一样。
"""

from __future__ import annotations

from datetime import UTC, date, datetime
from uuid import UUID

from fastapi import APIRouter, Request, Response
from pydantic import BaseModel

from aim_api.contexts.family.adapters.inbound.http.router import (
    FamilyResponse,
    _family_response,
)
from aim_api.contexts.family.adapters.outbound.persistence.repositories import (
    SqlAlchemyFamilyRepository,
)
from aim_api.contexts.family.application.token import hash_invitation_token
from aim_api.contexts.identity.domain.account import Account
from aim_api.contexts.family.domain.events import FamilyEvent, FamilyEventKind
from aim_api.composition.family.membership import (
    create_empty_family,
    delete_family,
    detach_member,
    family_has_content,
)
from aim_api.contexts.family.domain.family import (
    Family,
    FamilyMember,
    FamilyMemberRole,
    FamilyMemberStatus,
)
from aim_api.contexts.family.domain.invitation import (
    Invitation,
    InvitationStatus,
    normalize_invitee_phone,
)
from aim_api.contexts.pregnancy.adapters.inbound.http.router import (
    PregnancyResponse,
    _response as pregnancy_response,
)
from aim_api.contexts.pregnancy.adapters.outbound.persistence.repositories import (
    SqlAlchemyPregnancyRepository,
)
from aim_api.contexts.pregnancy.domain.errors import DueDateOutOfRange
from aim_api.platform.auth.context import authenticate_active
from aim_api.platform.http.errors import ApiError, ConflictError, ForbiddenError, NotFoundError

router = APIRouter(tags=["family"])


class UnprocessableError(ApiError):
    status_code = 422
    code = "unprocessable"


class UpdatePregnancyRequest(BaseModel):
    due_date: date


class MeResponse(BaseModel):
    account_id: UUID
    family_id: UUID
    pregnancy_id: UUID | None
    role: FamilyMemberRole


@router.patch("/api/v1/pregnancies/{pregnancy_id}", response_model=PregnancyResponse)
async def update_pregnancy(
    pregnancy_id: UUID, payload: UpdatePregnancyRequest, request: Request
) -> PregnancyResponse:
    """家里任何在籍成员都能改预产期；改动记入家庭动态。"""
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        pregnancies = SqlAlchemyPregnancyRepository(session)
        families = SqlAlchemyFamilyRepository(session)
        pregnancy = await pregnancies.get_pregnancy(pregnancy_id)
        if pregnancy is None or not await families.is_active_member(
            pregnancy.family_id, actor.account_id
        ):
            raise ForbiddenError("不能修改这段孕期")
        try:
            previous = pregnancy.change_due_date(payload.due_date, today=datetime.now(UTC).date())
        except DueDateOutOfRange as error:
            raise UnprocessableError(str(error)) from error
        if previous != pregnancy.due_date:
            await pregnancies.save_due_date(pregnancy)
            await families.add_event(
                FamilyEvent.new(
                    pregnancy.family_id,
                    FamilyEventKind.due_date_changed,
                    actor=actor.account_id,
                    payload={"from": previous.isoformat(), "to": pregnancy.due_date.isoformat()},
                )
            )
            await session.commit()
        return pregnancy_response(pregnancy)


@router.get("/api/v1/me", response_model=MeResponse)
async def me(request: Request) -> MeResponse:
    """当前账号在哪个家庭、哪段孕期。被移出家庭后，App 靠它找回自己的新家庭。"""
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        families = SqlAlchemyFamilyRepository(session)
        family = await families.get_first_family_for_account(actor.account_id)
        if family is None:
            raise NotFoundError("account has no family")
        pregnancy = await SqlAlchemyPregnancyRepository(session).get_first_pregnancy_for_family(
            family.id
        )
        return MeResponse(
            account_id=actor.account_id,
            family_id=family.id,
            pregnancy_id=pregnancy.id if pregnancy else None,
            role=family.members[actor.account_id].role,
        )


# ---------------------------------------------------------------------------
# 邀请：被邀请人按手机号看到、接受或暂不；邀请人或管理员撤回
# ---------------------------------------------------------------------------

_ROLE_NAMES = {
    FamilyMemberRole.mother: "妈妈",
    FamilyMemberRole.father: "爸爸",
    FamilyMemberRole.other_caregiver: "家人",
}


def _display_name(member: FamilyMember | None) -> str:
    if member is None:
        return "家人"
    nickname = (member.nickname or "").strip()
    return nickname or _ROLE_NAMES[member.role]


class MyInvitationResponse(BaseModel):
    id: UUID
    family_id: UUID
    family_name: str
    inviter_name: str
    role: FamilyMemberRole
    expires_at: datetime
    status: str
    can_accept: bool
    #: 不能接受时给用户看的原因。
    blocked_reason: str | None


class MyInvitationsResponse(BaseModel):
    invitations: list[MyInvitationResponse]


def _closed_reason(invitation: Invitation, now: datetime) -> str | None:
    if invitation.status is InvitationStatus.revoked:
        return "这个邀请已被撤回"
    if invitation.status is InvitationStatus.accepted:
        return "这个邀请已经用过了"
    if invitation.status is InvitationStatus.expired or now >= invitation.expires_at:
        return "这个邀请已过期，请对方重新邀请"
    return None


async def _my_invitation(session, actor, invitation_id: UUID) -> Invitation:
    invitation = await SqlAlchemyFamilyRepository(session).get_invitation(invitation_id)
    # 不是发给自己的邀请当作不存在，不暴露别人的邀请。
    if invitation is None or invitation.invitee_phone != normalize_invitee_phone(actor.phone):
        raise NotFoundError("没有找到这个邀请")
    return invitation


@router.get("/api/v1/me/invitations", response_model=MyInvitationsResponse)
async def my_invitations(request: Request) -> MyInvitationsResponse:
    actor = await authenticate_active(request)
    now = datetime.now(UTC)
    async with request.app.state.database.session() as session:
        families = SqlAlchemyFamilyRepository(session)
        current = await families.get_first_family_for_account(actor.account_id)
        blocked = (
            await family_has_content(session, current.id, actor.account_id) if current else None
        )
        result: list[MyInvitationResponse] = []
        for invitation in await families.list_invitations_for_phone(
            normalize_invitee_phone(actor.phone)
        ):
            if not invitation.is_open(now) or (current and invitation.family_id == current.id):
                continue
            family = await families.get_family(invitation.family_id)
            if family is None:
                continue
            result.append(
                MyInvitationResponse(
                    id=invitation.id,
                    family_id=family.id,
                    family_name=family.name,
                    inviter_name=_display_name(family.members.get(invitation.invited_by)),
                    role=invitation.role,
                    expires_at=invitation.expires_at,
                    status=invitation.status.value,
                    can_accept=blocked is None,
                    blocked_reason=blocked,
                )
            )
        return MyInvitationsResponse(invitations=result)


@router.post("/api/v1/me/invitations/{invitation_id}/accept", response_model=MeResponse)
async def accept_my_invitation(invitation_id: UUID, request: Request) -> MeResponse:
    """接受邀请：原家庭必须没有内容，随后整个删掉，再加入新家庭。一个事务完成。"""
    actor = await authenticate_active(request)
    now = datetime.now(UTC)
    async with request.app.state.database.session() as session:
        families = SqlAlchemyFamilyRepository(session)
        invitation = await _my_invitation(session, actor, invitation_id)
        if reason := _closed_reason(invitation, now):
            raise ConflictError(reason)
        target = await join_family(session, actor, invitation, now)
        pregnancy = await SqlAlchemyPregnancyRepository(session).get_first_pregnancy_for_family(
            target.id
        )
        return MeResponse(
            account_id=actor.account_id,
            family_id=target.id,
            pregnancy_id=pregnancy.id if pregnancy else None,
            role=invitation.role,
        )


async def join_family(session, actor, invitation: Invitation, now: datetime) -> Family:
    """接受邀请的唯一实现，按手机号和按邀请码两条入口共用。

    原家庭没有内容才能接受；接受时删掉原家庭，再加入新家庭，一次提交。
    """
    families = SqlAlchemyFamilyRepository(session)
    # 与原来按邀请码接受的行为一致：账号行不存在时补建（直接签票的旧客户端与测试会这样）。
    await families.ensure_account(Account.register(actor.account_id, actor.phone, now=now))
    target = await families.get_family(invitation.family_id)
    if target is None:
        raise ConflictError("这个家庭已经不存在了")
    current = await families.get_first_family_for_account(actor.account_id)
    if current is not None and current.id == target.id:
        raise ConflictError("你已经在这个家庭里了")
    previous_member = current.members.get(actor.account_id) if current else None
    if current is not None:
        if blocked := await family_has_content(session, current.id, actor.account_id):
            raise ConflictError(blocked)
        await delete_family(session, current.id)

    joined = invitation.accept(actor.account_id, actor.phone, now)
    member = FamilyMember.active(
        actor.account_id,
        joined.role,
        nickname=previous_member.nickname if previous_member else None,
        joined_at=now,
    )
    await families.add_member(target.id, member)
    await families.save_invitation(invitation)
    await families.add_event(
        FamilyEvent.new(
            target.id,
            FamilyEventKind.member_joined,
            actor=actor.account_id,
            subject=actor.account_id,
            payload={"display_name": _display_name(member)},
            now=now,
        )
    )
    await session.commit()
    target.members[actor.account_id] = member
    return target


@router.post("/api/v1/me/invitations/{invitation_id}/decline", status_code=204)
async def decline_my_invitation(invitation_id: UUID, request: Request) -> Response:
    """「暂不」：不再自动弹出，过期前仍可在个人资料页接受。"""
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        invitation = await _my_invitation(session, actor, invitation_id)
        if invitation.status is InvitationStatus.pending:
            invitation.decline()
            await SqlAlchemyFamilyRepository(session).save_invitation(invitation)
            await session.commit()
        elif reason := _closed_reason(invitation, datetime.now(UTC)):
            raise ConflictError(reason)
    return Response(status_code=204)


@router.delete("/api/v1/families/{family_id}/invitations/{invitation_id}", status_code=204)
async def revoke_invitation(family_id: UUID, invitation_id: UUID, request: Request) -> Response:
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        families = SqlAlchemyFamilyRepository(session)
        family = await families.get_family(family_id)
        if family is None or not await families.is_active_member(family_id, actor.account_id):
            raise ForbiddenError("不是这个家庭的成员")
        invitation = await families.get_invitation(invitation_id)
        if invitation is None or invitation.family_id != family_id:
            raise NotFoundError("没有找到这个邀请")
        if actor.account_id not in (family.created_by, invitation.invited_by):
            raise ForbiddenError("只有管理员或发出邀请的人可以撤回")
        if not invitation.is_open():
            raise ConflictError(_closed_reason(invitation, datetime.now(UTC)) or "这个邀请已失效")
        invitation.revoke()
        await families.save_invitation(invitation)
        await session.commit()
    return Response(status_code=204)


# ---------------------------------------------------------------------------
# 离开家庭：自己退出，或管理员移出别人
# ---------------------------------------------------------------------------


async def _leave(
    session, family: Family, account_id: UUID, *, actor: UUID, kind: FamilyEventKind
) -> UUID:
    member = family.members[account_id]
    await detach_member(session, family.id, account_id)
    await SqlAlchemyFamilyRepository(session).add_event(
        FamilyEvent.new(
            family.id,
            kind,
            actor=actor,
            subject=account_id,
            payload={"display_name": _display_name(member)},
        )
    )
    return await create_empty_family(session, account_id, member.role, member.nickname)


@router.post("/api/v1/families/{family_id}/members/me/leave", response_model=MeResponse)
async def leave_family(family_id: UUID, request: Request) -> MeResponse:
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        families = SqlAlchemyFamilyRepository(session)
        family = await families.get_family(family_id)
        if family is None or not await families.is_active_member(family_id, actor.account_id):
            raise ForbiddenError("不是这个家庭的成员")
        active = [m for m in family.members.values() if m.status is FamilyMemberStatus.active]
        if len(active) <= 1:
            raise ConflictError("家里只剩你一个人，不能退出")
        role = family.members[actor.account_id].role
        new_family = await _leave(
            session, family, actor.account_id, actor=actor.account_id, kind=FamilyEventKind.member_left
        )
        await session.commit()
        return MeResponse(
            account_id=actor.account_id, family_id=new_family, pregnancy_id=None, role=role
        )


@router.delete("/api/v1/families/{family_id}/members/{account_id}", status_code=204)
async def remove_member(family_id: UUID, account_id: UUID, request: Request) -> Response:
    actor = await authenticate_active(request)
    async with request.app.state.database.session() as session:
        families = SqlAlchemyFamilyRepository(session)
        family = await families.get_family(family_id)
        if family is None or not await families.is_active_member(family_id, actor.account_id):
            raise ForbiddenError("不是这个家庭的成员")
        if family.created_by != actor.account_id:
            raise ForbiddenError("只有管理员可以移出成员")
        if account_id == actor.account_id:
            raise ConflictError("不能移出自己，请用「退出家庭」")
        target = family.members.get(account_id)
        if target is None or target.status is not FamilyMemberStatus.active:
            raise ConflictError("TA 已经不在家庭里了")
        await _leave(
            session, family, account_id, actor=actor.account_id, kind=FamilyEventKind.member_removed
        )
        await session.commit()
    return Response(status_code=204)


@router.post("/api/v1/family-invitations/{token}/accept", response_model=FamilyResponse)
async def accept_invitation_by_token(token: str, request: Request) -> FamilyResponse:
    """按邀请码接受。App 不用它（App 按手机号），保留给脚本和测试；规则与按手机号一致。"""
    actor = await authenticate_active(request)
    now = datetime.now(UTC)
    async with request.app.state.database.session() as session:
        families = SqlAlchemyFamilyRepository(session)
        invitation = await families.get_invitation_by_hash(hash_invitation_token(token))
        if invitation is None:
            raise NotFoundError("没有找到这个邀请")
        if invitation.invitee_phone != normalize_invitee_phone(actor.phone):
            raise ConflictError("这个邀请不是发给你的")
        if reason := _closed_reason(invitation, now):
            raise ConflictError(reason)
        family = await join_family(session, actor, invitation, now)
        return _family_response(family)
