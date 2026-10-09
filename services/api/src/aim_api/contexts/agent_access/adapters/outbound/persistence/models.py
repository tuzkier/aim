from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from sqlalchemy import JSON, DateTime, ForeignKey, Index, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from aim_api.platform.database.session import Base


class ToolInvocationModel(Base):
    __tablename__ = "tool_invocations"
    __table_args__ = (
        Index("ix_tool_invocations_session_call", "session_id", "call_id", unique=True),
    )

    operation_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    session_id: Mapped[str] = mapped_column(String(160), nullable=False)
    call_id: Mapped[str] = mapped_column(String(160), nullable=False)
    tool_name: Mapped[str] = mapped_column(String(120), nullable=False)
    request_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    status: Mapped[str] = mapped_column(String(30), nullable=False)
    result_json: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    #: 这次调用代表谁、作用在哪段孕期。撤销时据此校验归属。
    account_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
    family_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
    pregnancy_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
    #: 已被撤销的时刻。再次撤销时直接返回成功。
    undone_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class AgentSessionModel(Base):
    """一段 AIM 对话的元信息。

    对话内容留在 Eve（可用 /eve/v1/session/{id}/stream?startIndex=0 完整重放），
    这里只存引用。一份数据两处存迟早不一致，而且对话涉及隐私，少存一份就少一处
    泄漏面。
    """

    __tablename__ = "agent_sessions"
    __table_args__ = (
        Index("ix_agent_sessions_account_active", "account_id", "last_active_at"),
        Index("uq_agent_sessions_eve_id", "eve_session_id", unique=True),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    #: 按账号隔离，不是按家庭——孕期会问很私人的事。
    account_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False
    )
    #: 只为按家庭清理数据方便，不参与鉴权。
    family_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("families.id", ondelete="CASCADE"), nullable=False
    )
    eve_session_id: Mapped[str] = mapped_column(Text, nullable=False)
    title: Mapped[str] = mapped_column(String(80), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    last_active_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
