from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from sqlalchemy import JSON, DateTime, Index, Integer, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from aim_api.platform.database.session import Base


class RecordModel(Base):
    __tablename__ = "records"
    __table_args__ = (
        Index("ix_records_pregnancy_occurred_at", "pregnancy_id", "occurred_at"),
        Index("ix_records_family_visibility", "family_id", "visibility"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    pregnancy_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    family_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    author_account_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    record_type: Mapped[str] = mapped_column(String(20), nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    visibility: Mapped[str] = mapped_column(String(20), nullable=False)
    title: Mapped[str | None] = mapped_column(String(200), nullable=True)
    content: Mapped[str | None] = mapped_column(String(5000), nullable=True)
    structured_data: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    attachment_refs: Mapped[list[str]] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class AttachmentModel(Base):
    """与 records 表一致不设外键：注销清理按表逐个显式删除。"""

    __tablename__ = "attachments"
    __table_args__ = (
        Index("ix_attachments_record", "record_id"),
        Index("ix_attachments_family", "family_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    family_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    pregnancy_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    uploaded_by: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
    media_type: Mapped[str] = mapped_column(String(40), nullable=False)
    byte_size: Mapped[int] = mapped_column(Integer, nullable=False)
    record_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
