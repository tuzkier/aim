from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlalchemy import and_, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from aim_api.contexts.family.adapters.outbound.persistence.repositories import (
    SqlAlchemyFamilyRepository,
)
from aim_api.contexts.family.application.ports import PersistenceConflict
from aim_api.contexts.pregnancy.adapters.outbound.persistence.repositories import (
    SqlAlchemyPregnancyRepository,
)
from aim_api.contexts.records.adapters.outbound.persistence.models import (
    AttachmentModel,
    RecordModel,
)
from aim_api.contexts.records.domain.attachment import Attachment
from aim_api.contexts.records.domain.errors import RecordAccessDenied, RecordValidationError
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility


class SqlAlchemyRecordsRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def add_record(self, record: Record) -> None:
        self.session.add(_to_model(record))

    async def get_visible_record(
        self, record_id: UUID, family_id: UUID, account_id: UUID
    ) -> Record | None:
        model = await self.session.scalar(
            select(RecordModel).where(
                RecordModel.id == record_id,
                RecordModel.family_id == family_id,
                RecordModel.deleted_at.is_(None),
                _visibility_clause(account_id),
            )
        )
        return _to_record(model) if model else None

    async def list_visible_records(
        self,
        family_id: UUID,
        account_id: UUID,
        *,
        pregnancy_id: UUID | None = None,
        record_type: RecordType | None = None,
        occurred_from: datetime | None = None,
        occurred_until: datetime | None = None,
    ) -> list[Record]:
        clauses = [
            RecordModel.family_id == family_id,
            RecordModel.deleted_at.is_(None),
            _visibility_clause(account_id),
        ]
        if pregnancy_id is not None:
            clauses.append(RecordModel.pregnancy_id == pregnancy_id)
        if record_type is not None:
            clauses.append(RecordModel.record_type == record_type.value)
        if occurred_from is not None:
            clauses.append(RecordModel.occurred_at >= occurred_from)
        if occurred_until is not None:
            clauses.append(RecordModel.occurred_at <= occurred_until)
        models = (
            await self.session.scalars(
                select(RecordModel)
                .where(and_(*clauses))
                .order_by(RecordModel.occurred_at.desc(), RecordModel.id.desc())
            )
        ).all()
        return [_to_record(model) for model in models]

    async def save_record(self, record: Record, account_id: UUID) -> None:
        record.assert_can_mutate(account_id)
        record.assert_attachment_refs_reserved()
        if record.deleted_at is not None:
            raise RecordValidationError("soft-deleted records cannot be saved")
        result = await self.session.execute(
            update(RecordModel)
            .where(
                RecordModel.id == record.id,
                RecordModel.author_account_id == account_id,
                RecordModel.deleted_at.is_(None),
            )
            .values(
                occurred_at=record.occurred_at,
                visibility=record.visibility.value,
                title=record.title,
                content=record.content,
                structured_data=record.structured_data,
                attachment_refs=record.attachment_refs,
                updated_at=record.updated_at,
            )
        )
        if result.rowcount != 1:
            raise RecordAccessDenied("record cannot be updated by this account")

    async def soft_delete(self, record: Record, account_id: UUID) -> None:
        record.assert_can_mutate(account_id)
        result = await self.session.execute(
            update(RecordModel)
            .where(
                RecordModel.id == record.id,
                RecordModel.author_account_id == account_id,
                RecordModel.deleted_at.is_(None),
            )
            .values(deleted_at=record.deleted_at, updated_at=record.updated_at)
        )
        if result.rowcount != 1:
            raise RecordAccessDenied("record cannot be deleted by this account")


class SqlAlchemyAttachmentRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def add(self, attachment: Attachment) -> None:
        self.session.add(
            AttachmentModel(
                id=attachment.id,
                family_id=attachment.family_id,
                pregnancy_id=attachment.pregnancy_id,
                uploaded_by=attachment.uploaded_by,
                media_type=attachment.media_type,
                byte_size=attachment.byte_size,
                record_id=attachment.record_id,
                created_at=attachment.created_at,
            )
        )

    async def get(self, attachment_id: UUID) -> Attachment | None:
        model = await self.session.get(AttachmentModel, attachment_id)
        if model is None:
            return None
        return Attachment(
            id=model.id,
            family_id=model.family_id,
            pregnancy_id=model.pregnancy_id,
            uploaded_by=model.uploaded_by,
            media_type=model.media_type,
            byte_size=model.byte_size,
            record_id=model.record_id,
            created_at=model.created_at,
        )

    async def attach(self, attachment_ids: list[UUID], record_id: UUID) -> None:
        await self.session.execute(
            update(AttachmentModel)
            .where(AttachmentModel.id.in_(attachment_ids), AttachmentModel.record_id.is_(None))
            .values(record_id=record_id)
        )


class SqlAlchemyRecordsUnitOfWork:
    def __init__(self, session: AsyncSession) -> None:
        self.repository = SqlAlchemyRecordsRepository(session)
        self.attachments = SqlAlchemyAttachmentRepository(session)
        self.family_membership = SqlAlchemyFamilyRepository(session)
        self.pregnancy_ownership = SqlAlchemyPregnancyRepository(session)
        self._session = session

    async def commit(self) -> None:
        try:
            await self._session.commit()
        except IntegrityError as error:
            await self._session.rollback()
            raise PersistenceConflict("records persistence constraint failed") from error

    async def rollback(self) -> None:
        await self._session.rollback()


def _visibility_clause(account_id: UUID):
    return or_(
        RecordModel.visibility == RecordVisibility.family.value,
        RecordModel.author_account_id == account_id,
    )


def _to_model(record: Record) -> RecordModel:
    record.assert_attachment_refs_reserved()
    return RecordModel(
        id=record.id,
        pregnancy_id=record.pregnancy_id,
        family_id=record.family_id,
        author_account_id=record.author_account_id,
        record_type=record.record_type.value,
        occurred_at=record.occurred_at,
        visibility=record.visibility.value,
        title=record.title,
        content=record.content,
        structured_data=record.structured_data,
        attachment_refs=record.attachment_refs,
        created_at=record.created_at,
        updated_at=record.updated_at,
        deleted_at=record.deleted_at,
    )


def _to_record(model: RecordModel) -> Record:
    return Record(
        id=model.id,
        pregnancy_id=model.pregnancy_id,
        family_id=model.family_id,
        author_account_id=model.author_account_id,
        record_type=RecordType(model.record_type),
        occurred_at=model.occurred_at,
        visibility=RecordVisibility(model.visibility),
        title=model.title,
        content=model.content,
        structured_data=dict(model.structured_data),
        attachment_refs=list(model.attachment_refs),
        created_at=model.created_at,
        updated_at=model.updated_at,
        deleted_at=model.deleted_at,
    )
