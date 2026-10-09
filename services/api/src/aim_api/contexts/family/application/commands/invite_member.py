from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from secrets import token_urlsafe
from uuid import UUID, uuid4

from aim_api.contexts.family.application.ports import FamilyUnitOfWork
from aim_api.contexts.family.application.token import hash_invitation_token
from aim_api.contexts.family.domain.family import FamilyMemberRole
from aim_api.contexts.family.domain.invitation import Invitation


@dataclass(frozen=True, slots=True)
class InviteMemberCommand:
    family_id: UUID
    invited_by: UUID
    invitee_phone: str
    role: FamilyMemberRole
    now: datetime | None = None


@dataclass(frozen=True, slots=True)
class InvitationResult:
    invitation: Invitation
    token: str


async def execute(command: InviteMemberCommand, uow: FamilyUnitOfWork) -> InvitationResult:
    family = await uow.repository.get_family(command.family_id)
    if family is None:
        raise ValueError("family does not exist")
    family.active_member(command.invited_by)

    invitee = await uow.repository.get_account_by_phone(command.invitee_phone)
    if invitee is not None and invitee.id in family.members:
        from aim_api.contexts.family.domain.errors import DuplicateFamilyMember

        raise DuplicateFamilyMember("account already belongs to this family")

    raw_token = token_urlsafe(32)
    invitation = Invitation.create(
        invitation_id=uuid4(),
        family_id=family.id,
        invited_by=command.invited_by,
        invitee_phone=command.invitee_phone,
        role=command.role,
        token_hash=hash_invitation_token(raw_token),
        created_at=command.now,
    )
    # 不再预先插入「待确认」成员：被邀请人在自己的 App 里看到邀请，接受时才入籍。
    await uow.repository.revoke_open_invitations(family.id, invitation.invitee_phone)
    await uow.repository.add_invitation(invitation)
    await uow.commit()
    return InvitationResult(invitation=invitation, token=raw_token)
