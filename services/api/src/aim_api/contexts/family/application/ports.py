from __future__ import annotations

from typing import Protocol
from uuid import UUID

from aim_api.contexts.family.domain.family import Family, FamilyMember
from aim_api.contexts.family.domain.invitation import Invitation
from aim_api.contexts.identity.domain.account import Account


class PersistenceConflict(Exception):
    """Raised when a database uniqueness constraint beats an application pre-check."""


class FamilyRepositoryPort(Protocol):
    async def ensure_account(self, account: Account) -> Account: ...

    async def get_account(self, account_id: UUID) -> Account | None: ...

    async def get_account_by_phone(self, phone: str) -> Account | None: ...

    async def add_family(self, family: Family) -> None: ...

    async def get_family(self, family_id: UUID) -> Family | None: ...

    async def add_member(self, family_id: UUID, member: FamilyMember) -> None: ...

    async def activate_member(self, family_id: UUID, account_id: UUID, joined_at) -> None: ...

    async def get_invitation_by_hash(self, token_hash: str) -> Invitation | None: ...

    async def add_invitation(self, invitation: Invitation) -> None: ...

    async def save_invitation(self, invitation: Invitation) -> None: ...


class FamilyUnitOfWork(Protocol):
    repository: FamilyRepositoryPort

    async def commit(self) -> None: ...

    async def rollback(self) -> None: ...
