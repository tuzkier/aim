from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from aim_api.contexts.agent_access.adapters.outbound.persistence.models import ToolInvocationModel
from aim_api.contexts.agent_access.domain.tool_invocation import (
    ToolInvocation,
    ToolInvocationStatus,
)


class SqlAlchemyToolInvocationRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get(self, session_id: str, call_id: str) -> ToolInvocation | None:
        model = await self.session.scalar(
            select(ToolInvocationModel).where(
                ToolInvocationModel.session_id == session_id,
                ToolInvocationModel.call_id == call_id,
            )
        )
        return _to_domain(model) if model else None

    async def add(self, invocation: ToolInvocation) -> None:
        self.session.add(
            ToolInvocationModel(
                operation_id=invocation.operation_id,
                session_id=invocation.session_id,
                call_id=invocation.call_id,
                tool_name=invocation.tool_name,
                request_hash=invocation.request_hash,
                status=invocation.status.value,
                result_json=invocation.result,
                created_at=invocation.created_at,
                account_id=invocation.account_id,
                family_id=invocation.family_id,
                pregnancy_id=invocation.pregnancy_id,
                undone_at=invocation.undone_at,
            )
        )

    async def get_by_operation(self, operation_id: UUID) -> ToolInvocation | None:
        model = await self.session.get(ToolInvocationModel, operation_id)
        return _to_domain(model) if model else None

    async def mark_undone(self, operation_id: UUID, at: datetime) -> None:
        await self.session.execute(
            update(ToolInvocationModel)
            .where(ToolInvocationModel.operation_id == operation_id)
            .values(undone_at=at)
        )

    async def commit(self) -> None:
        try:
            await self.session.commit()
        except IntegrityError:
            await self.session.rollback()
            raise


def _to_domain(model: ToolInvocationModel) -> ToolInvocation:
    return ToolInvocation(
        operation_id=model.operation_id,
        session_id=model.session_id,
        call_id=model.call_id,
        tool_name=model.tool_name,
        request_hash=model.request_hash,
        status=ToolInvocationStatus(model.status),
        result=model.result_json,
        created_at=model.created_at,
        account_id=model.account_id,
        family_id=model.family_id,
        pregnancy_id=model.pregnancy_id,
        undone_at=model.undone_at,
    )
