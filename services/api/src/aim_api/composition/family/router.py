"""跨模块的家庭接口：改预产期、我是谁、邀请、离开家庭、成员详情、家庭动态。

这些操作同时碰家庭、孕期、待办、记录几张表，放在组合层，和 today 一样。
"""

from __future__ import annotations

from datetime import UTC, date, datetime
from uuid import UUID

from fastapi import APIRouter, Request
from pydantic import BaseModel

from aim_api.contexts.family.adapters.outbound.persistence.repositories import (
    SqlAlchemyFamilyRepository,
)
from aim_api.contexts.family.domain.events import FamilyEvent, FamilyEventKind
from aim_api.contexts.family.domain.family import FamilyMemberRole
from aim_api.contexts.pregnancy.adapters.inbound.http.router import (
    PregnancyResponse,
    _response as pregnancy_response,
)
from aim_api.contexts.pregnancy.adapters.outbound.persistence.repositories import (
    SqlAlchemyPregnancyRepository,
)
from aim_api.contexts.pregnancy.domain.errors import DueDateOutOfRange
from aim_api.platform.auth.context import authenticate_active
from aim_api.platform.http.errors import ApiError, ForbiddenError, NotFoundError

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
