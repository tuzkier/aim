"""AIM 会话列表。

对话内容留在 Eve；这里只登记「有过哪些会话」，好让用户翻回去。
单独成文件而不是塞进 agent_tools 的 router——那个文件管的是工具调用鉴权与执行，
和「列出我的对话」没有任何共同的关注点。
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

from fastapi import APIRouter, Request, Response, status
from pydantic import BaseModel, Field
from sqlalchemy import select

from aim_api.contexts.agent_access.adapters.outbound.persistence.models import (
    AgentSessionModel,
)
from aim_api.contexts.family.adapters.outbound.persistence.repositories import (
    SqlAlchemyFamilyUnitOfWork,
)
from aim_api.platform.auth.context import authenticate_active
from aim_api.platform.database.session import Database
from aim_api.platform.http.errors import NotFoundError

router = APIRouter(tags=["agent-sessions"])


class CreateSessionRequest(BaseModel):
    eve_session_id: str = Field(min_length=1, max_length=200)
    title: str = Field(min_length=1, max_length=80)


class UpdateSessionRequest(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=80)
    #: 只想把它顶到列表最前面（回到这段继续聊），不改标题。
    touch: bool = False


class SessionResponse(BaseModel):
    id: UUID
    eve_session_id: str
    title: str
    created_at: datetime
    last_active_at: datetime


class SessionListResponse(BaseModel):
    sessions: list[SessionResponse]


def _to_response(model: AgentSessionModel) -> SessionResponse:
    return SessionResponse(
        id=model.id,
        eve_session_id=model.eve_session_id,
        title=model.title,
        created_at=model.created_at,
        last_active_at=model.last_active_at,
    )


@router.get("/api/v1/agent/sessions", response_model=SessionListResponse)
async def list_sessions(request: Request) -> SessionListResponse:
    actor = await authenticate_active(request)
    database: Database = request.app.state.database
    async with database.session() as session:
        # 只列当前家庭里的对话：退出或被移出后，在原家庭里聊的内容不再出现。
        family = await SqlAlchemyFamilyUnitOfWork(session).repository.get_first_family_for_account(
            actor.account_id
        )
        if family is None:
            return SessionListResponse(sessions=[])
        rows = await session.scalars(
            select(AgentSessionModel)
            .where(
                AgentSessionModel.account_id == actor.account_id,
                AgentSessionModel.family_id == family.id,
            )
            .order_by(AgentSessionModel.last_active_at.desc())
        )
        return SessionListResponse(sessions=[_to_response(row) for row in rows])


@router.post(
    "/api/v1/agent/sessions", response_model=SessionResponse, status_code=status.HTTP_201_CREATED
)
async def create_session(
    payload: CreateSessionRequest, request: Request, response: Response
) -> SessionResponse:
    actor = await authenticate_active(request)
    database: Database = request.app.state.database
    now = datetime.now(UTC)

    async with database.session() as session:
        existing = await session.scalar(
            select(AgentSessionModel).where(
                AgentSessionModel.eve_session_id == payload.eve_session_id
            )
        )
        if existing is not None:
            # 客户端重试或并发都可能重复登记。重复不是错误——
            # 让用户看到一次失败，只会让他们以为对话没存上。
            if existing.account_id == actor.account_id:
                existing.last_active_at = now
                await session.commit()
                response.status_code = status.HTTP_200_OK
                return _to_response(existing)
            # 别人的会话 id：当作不存在，不确认它的归属。
            raise NotFoundError(payload.eve_session_id)

        family_uow = SqlAlchemyFamilyUnitOfWork(session)
        family = await family_uow.repository.get_first_family_for_account(actor.account_id)
        if family is None:
            raise NotFoundError("family")

        model = AgentSessionModel(
            id=uuid4(),
            account_id=actor.account_id,
            family_id=family.id,
            eve_session_id=payload.eve_session_id,
            title=payload.title,
            created_at=now,
            last_active_at=now,
        )
        session.add(model)
        await session.commit()
        return _to_response(model)


async def _own_session(session, account_id: UUID, session_id: UUID) -> AgentSessionModel:
    """按 id 取自己的会话。

    不属于自己时返回 404 而不是 403：403 等于确认「这个 id 存在」，
    会话 id 就成了可探测的。
    """
    model = await session.scalar(
        select(AgentSessionModel).where(
            AgentSessionModel.id == session_id,
            AgentSessionModel.account_id == account_id,
        )
    )
    if model is None:
        raise NotFoundError(str(session_id))
    return model


@router.patch("/api/v1/agent/sessions/{session_id}", response_model=SessionResponse)
async def update_session(
    session_id: UUID, payload: UpdateSessionRequest, request: Request
) -> SessionResponse:
    actor = await authenticate_active(request)
    database: Database = request.app.state.database
    async with database.session() as session:
        model = await _own_session(session, actor.account_id, session_id)
        if payload.title is not None:
            model.title = payload.title
        if payload.touch or payload.title is not None:
            model.last_active_at = datetime.now(UTC)
        await session.commit()
        return _to_response(model)


@router.delete("/api/v1/agent/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_session(session_id: UUID, request: Request) -> Response:
    actor = await authenticate_active(request)
    database: Database = request.app.state.database
    async with database.session() as session:
        model = await _own_session(session, actor.account_id, session_id)
        # 只从列表移除，不动 Eve 那边的对话数据——
        # 我们没有权限决定删除别人系统里的东西。
        await session.delete(model)
        await session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
