from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from aim_api.contexts.family.application.ports import FamilyUnitOfWork
from aim_api.contexts.family.application.token import hash_invitation_token
from aim_api.contexts.family.domain.family import FamilyMember, FamilyMemberStatus
from aim_api.contexts.identity.domain.account import Account


@dataclass(frozen=True, slots=True)
class AcceptInvitationCommand:
    invitation_token: str
    account_id: UUID
    phone: str
    now: datetime | None = None


async def execute(command: AcceptInvitationCommand, uow: FamilyUnitOfWork):
    account = Account.register(command.account_id, command.phone, now=command.now)
    await uow.repository.ensure_account(account)
    invitation = await uow.repository.get_invitation_by_hash(
        hash_invitation_token(command.invitation_token)
    )
    if invitation is None:
        from aim_api.contexts.family.domain.errors import InvitationNotFound

        raise InvitationNotFound("invitation does not exist")

    family = await uow.repository.get_family(invitation.family_id)
    if family is None:
        raise ValueError("family does not exist")
    existing = family.members.get(command.account_id)
    if existing is not None and existing.status is FamilyMemberStatus.active:
        from aim_api.contexts.family.domain.errors import DuplicateFamilyMember

        raise DuplicateFamilyMember("account already belongs to this family")

    joined = invitation.accept(command.account_id, command.phone, command.now)
    if existing is None:
        family.add_member(
            FamilyMember.active(command.account_id, joined.role, joined_at=joined.joined_at)
        )
        await uow.repository.add_member(family.id, family.members[command.account_id])
    else:
        family.activate_member(command.account_id, joined.joined_at)
        await uow.repository.activate_member(family.id, command.account_id, joined.joined_at)
    await uow.repository.save_invitation(invitation)
    await uow.commit()
    return family
