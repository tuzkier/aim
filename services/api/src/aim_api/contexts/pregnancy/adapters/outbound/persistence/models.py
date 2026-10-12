from __future__ import annotations

from datetime import UTC, date, datetime
from typing import Any
from uuid import UUID

from sqlalchemy import JSON, Date, DateTime, ForeignKey, Index, Integer, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from aim_api.platform.database.session import Base


def utc_now() -> datetime:
    return datetime.now(UTC)


class PregnancyModel(Base):
    __tablename__ = "pregnancies"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    family_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    due_date: Mapped[date] = mapped_column(Date, nullable=False)
    created_by: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    birth_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    birth_revision: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)


class PregnancyFactModel(Base):
    __tablename__ = "pregnancy_facts"
    __table_args__ = (Index("ix_pregnancy_facts_pregnancy_key", "pregnancy_id", "fact_key"),)

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    pregnancy_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("pregnancies.id", ondelete="CASCADE"), nullable=False
    )
    fact_key: Mapped[str] = mapped_column(String(120), nullable=False)
    value_json: Mapped[Any] = mapped_column(JSON, nullable=False)
    source: Mapped[str] = mapped_column(String(30), nullable=False)
    priority: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(String(30), nullable=False)
    observed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    recorded_by_account_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    supersedes_fact_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
