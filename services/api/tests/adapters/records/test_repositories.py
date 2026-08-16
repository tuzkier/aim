from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

import pytest
from sqlalchemy.dialects import postgresql

from aim_api.contexts.records.adapters.outbound.persistence.repositories import (
    SqlAlchemyRecordsRepository,
)
from aim_api.contexts.records.domain.record import RecordType


class EmptyScalars:
    def all(self):
        return []


class CapturingSession:
    statement = None

    async def scalars(self, statement):
        self.statement = statement
        return EmptyScalars()


@pytest.mark.asyncio
async def test_list_visible_records_filters_deleted_private_type_and_date_rows() -> None:
    session = CapturingSession()
    repository = SqlAlchemyRecordsRepository(session)  # type: ignore[arg-type]
    account_id = UUID("00000000-0000-0000-0000-000000000004")

    await repository.list_visible_records(
        UUID("00000000-0000-0000-0000-000000000003"),
        account_id,
        pregnancy_id=UUID("00000000-0000-0000-0000-000000000002"),
        record_type=RecordType.symptom,
        occurred_from=datetime(2026, 8, 1, tzinfo=UTC),
        occurred_until=datetime(2026, 8, 16, tzinfo=UTC),
    )

    sql = str(
        session.statement.compile(
            dialect=postgresql.dialect(), compile_kwargs={"literal_binds": True}
        )
    )
    assert "records.deleted_at IS NULL" in sql
    assert "records.visibility = 'family' OR records.author_account_id" in sql
    assert "records.record_type = 'symptom'" in sql
    assert "records.occurred_at >= '2026-08-01 00:00:00+00:00'" in sql
    assert "records.occurred_at <= '2026-08-16 00:00:00+00:00'" in sql
