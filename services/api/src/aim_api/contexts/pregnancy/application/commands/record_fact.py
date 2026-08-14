from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

from aim_api.contexts.pregnancy.application.ports import PregnancyUnitOfWork
from aim_api.contexts.pregnancy.domain.errors import PregnancyAccessDenied, PregnancyNotFound
from aim_api.contexts.pregnancy.domain.fact import FactEvidence, FactRecordResult, FactSource


@dataclass(frozen=True, slots=True)
class RecordFactCommand:
    pregnancy_id: UUID
    account_id: UUID
    key: str
    value: Any
    source: FactSource
    observed_at: datetime | None = None
    now: datetime | None = None


async def execute(command: RecordFactCommand, uow: PregnancyUnitOfWork) -> FactRecordResult:
    pregnancy = await uow.repository.get_pregnancy(command.pregnancy_id)
    if pregnancy is None:
        raise PregnancyNotFound("pregnancy does not exist")
    if not await uow.family_membership.is_active_member(pregnancy.family_id, command.account_id):
        raise PregnancyAccessDenied("account cannot write this pregnancy")
    observed_at = command.observed_at or command.now or datetime.now(UTC)
    result = pregnancy.record_fact(
        FactEvidence(uuid4(), command.key, command.value, command.source, observed_at),
        now=command.now,
    )
    await uow.repository.save_fact_result(command.pregnancy_id, result, command.account_id)
    await uow.commit()
    return result
