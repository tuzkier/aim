from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID, uuid4

from aim_api.contexts.family.application.ports import FamilyUnitOfWork
from aim_api.contexts.family.domain.family import Family, FamilyMember, FamilyMemberRole
from aim_api.contexts.identity.domain.account import Account


@dataclass(frozen=True, slots=True)
class CreateFamilyCommand:
    account_id: UUID
    phone: str
    name: str
    role: FamilyMemberRole
    password_hash: str = ""
    nickname: str | None = None
    now: datetime | None = None


async def execute(command: CreateFamilyCommand, uow: FamilyUnitOfWork) -> Family:
    account = Account.register(
        command.account_id,
        command.phone,
        password_hash=command.password_hash,
        now=command.now,
    )
    await uow.repository.ensure_account(account)
    family = Family.create(uuid4(), command.name, command.account_id, command.now)
    await uow.repository.add_family(family)
    await uow.repository.add_member(
        family.id,
        FamilyMember.active(
            command.account_id,
            command.role,
            nickname=command.nickname,
            joined_at=command.now,
        ),
    )
    await uow.commit()
    return family
