from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest

from aim_api.contexts.records.application.commands.delete_record import DeleteRecordCommand
from aim_api.contexts.records.application.commands.delete_record import execute as delete_record
from aim_api.contexts.records.application.queries.get_record import GetRecordQuery
from aim_api.contexts.records.application.queries.get_record import execute as get_record
from aim_api.contexts.records.domain.errors import RecordAccessDenied, RecordNotFound
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility


NOW = datetime(2026, 8, 16, 9, 0, tzinfo=UTC)


def make_record(visibility: RecordVisibility = RecordVisibility.family) -> Record:
    return Record.create(
        record_id=UUID("00000000-0000-0000-0000-000000000001"),
        pregnancy_id=UUID("00000000-0000-0000-0000-000000000002"),
        family_id=UUID("00000000-0000-0000-0000-000000000003"),
        author_account_id=UUID("00000000-0000-0000-0000-000000000004"),
        record_type=RecordType.symptom,
        occurred_at=NOW,
        visibility=visibility,
        structured_data={"symptoms": ["nausea"], "severity": 3},
        now=NOW,
    )


class FakeRepository:
    def __init__(self, record: Record) -> None:
        self.record = record
        self.deleted_by: UUID | None = None

    async def get_visible_record(self, record_id, family_id, account_id):
        if (
            record_id == self.record.id
            and family_id == self.record.family_id
            and self.record.is_visible_to(account_id)
        ):
            return self.record
        return None

    async def soft_delete(self, record, account_id):
        record.assert_can_mutate(account_id)
        self.deleted_by = account_id


class FakeMembership:
    def __init__(self, allowed: bool) -> None:
        self.allowed = allowed

    async def is_active_member(self, family_id, account_id):
        return self.allowed


class FakeUow:
    def __init__(self, record: Record, *, member: bool) -> None:
        self.repository = FakeRepository(record)
        self.family_membership = FakeMembership(member)
        self.committed = False

    async def commit(self):
        self.committed = True

    async def rollback(self):
        pass


@pytest.mark.asyncio
async def test_known_family_non_member_cannot_read_family_record() -> None:
    record = make_record()
    uow = FakeUow(record, member=False)

    with pytest.raises(RecordAccessDenied):
        await get_record(
            GetRecordQuery(record_id=record.id, family_id=record.family_id, account_id=uuid4()), uow
        )


@pytest.mark.asyncio
async def test_family_member_can_delete_family_record() -> None:
    record = make_record()
    uow = FakeUow(record, member=True)
    member_id = uuid4()

    await delete_record(
        DeleteRecordCommand(
            record_id=record.id, family_id=record.family_id, account_id=member_id, deleted_at=NOW
        ),
        uow,
    )

    assert uow.repository.deleted_by == member_id
    assert uow.committed is True


@pytest.mark.asyncio
async def test_delete_command_hides_private_record_from_non_author() -> None:
    record = make_record(RecordVisibility.private)
    uow = FakeUow(record, member=True)

    with pytest.raises(RecordNotFound):
        await delete_record(
            DeleteRecordCommand(
                record_id=record.id,
                family_id=record.family_id,
                account_id=uuid4(),
                deleted_at=NOW,
            ),
            uow,
        )

    assert uow.repository.deleted_by is None
    assert uow.committed is False
