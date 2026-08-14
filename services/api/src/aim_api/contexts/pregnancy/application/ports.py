from __future__ import annotations

from typing import Protocol
from uuid import UUID

from aim_api.contexts.pregnancy.domain.fact import FactRecordResult
from aim_api.contexts.pregnancy.domain.pregnancy import Pregnancy


class PregnancyRepositoryPort(Protocol):
    async def add_pregnancy(self, pregnancy: Pregnancy) -> None: ...

    async def get_pregnancy(self, pregnancy_id: UUID) -> Pregnancy | None: ...

    async def save_fact_result(
        self, pregnancy_id: UUID, result: FactRecordResult, recorded_by: UUID
    ) -> None: ...


class FamilyMembershipPort(Protocol):
    async def is_active_member(self, family_id: UUID, account_id: UUID) -> bool: ...


class PregnancyUnitOfWork(Protocol):
    repository: PregnancyRepositoryPort
    family_membership: FamilyMembershipPort

    async def commit(self) -> None: ...

    async def rollback(self) -> None: ...
