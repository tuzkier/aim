from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from sqlalchemy import JSON, DateTime, Index, String, Uuid
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
