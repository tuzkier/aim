from __future__ import annotations

from datetime import date, datetime
from typing import Protocol
from uuid import UUID

from aim_api.contexts.records.domain.attachment import Attachment
from aim_api.contexts.records.domain.record import Record, RecordType


class RecordsRepositoryPort(Protocol):
    async def baby_birth_date(self, baby_id: UUID, pregnancy_id: UUID, family_id: UUID) -> date | None: ...

    async def reserve_memory_slot(self, family_id: UUID) -> None: ...

    async def add_record(self, record: Record) -> None: ...

    async def get_visible_record(
        self, record_id: UUID, family_id: UUID, account_id: UUID
    ) -> Record | None: ...

    async def list_visible_records(
        self,
        family_id: UUID,
        account_id: UUID,
        *,
        pregnancy_id: UUID | None = None,
        record_type: RecordType | None = None,
        occurred_from: datetime | None = None,
        occurred_until: datetime | None = None,
    ) -> list[Record]: ...

    async def save_record(self, record: Record, account_id: UUID) -> None: ...

    async def soft_delete(self, record: Record, account_id: UUID) -> None: ...


class FamilyMembershipPort(Protocol):
    async def is_active_member(self, family_id: UUID, account_id: UUID) -> bool: ...


class PregnancyOwnershipPort(Protocol):
    async def get_pregnancy(self, pregnancy_id: UUID): ...


class AttachmentRepositoryPort(Protocol):
    async def add(self, attachment: Attachment) -> None: ...

    async def get(self, attachment_id: UUID) -> Attachment | None: ...

    async def attach(self, attachment_ids: list[UUID], record_id: UUID) -> None: ...


class AttachmentStoragePort(Protocol):
    def save(self, attachment_id: UUID, data: bytes) -> None: ...

    def read(self, attachment_id: UUID) -> bytes | None: ...

    def delete(self, attachment_id: UUID) -> None: ...

    def list_files(self) -> list[tuple[UUID, float]]: ...


class RecordsUnitOfWork(Protocol):
    repository: RecordsRepositoryPort
    attachments: AttachmentRepositoryPort
    family_membership: FamilyMembershipPort
    pregnancy_ownership: PregnancyOwnershipPort

    async def commit(self) -> None: ...

    async def rollback(self) -> None: ...
