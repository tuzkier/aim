from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from uuid import UUID

from aim_api.contexts.family.domain.errors import (
    InvitationExpired,
    InvitationUsed,
    InviteeMismatch,
)
from aim_api.contexts.family.domain.family import FamilyMemberRole


class InvitationStatus(StrEnum):
    pending = "pending"
    accepted = "accepted"
    expired = "expired"


def normalize_invitee_phone(phone: str) -> str:
    value = phone.strip().replace(" ", "").replace("-", "")
    if value.startswith("+86"):
        value = value[3:]
    if not re.fullmatch(r"[0-9]{6,20}", value):
        raise ValueError("invitee_phone must contain 6 to 20 digits")
    return value


@dataclass(frozen=True, slots=True)
class FamilyMemberInvited:
    invitation_id: UUID
    family_id: UUID
    invitee_phone: str
    role: FamilyMemberRole
    expires_at: datetime


@dataclass(frozen=True, slots=True)
class FamilyMemberJoined:
    invitation_id: UUID
    family_id: UUID
    account_id: UUID
    role: FamilyMemberRole
    joined_at: datetime


@dataclass(slots=True)
class Invitation:
    id: UUID
    family_id: UUID
    invited_by: UUID
    invitee_phone: str
    role: FamilyMemberRole
    token_hash: str
    created_at: datetime
    expires_at: datetime
    status: InvitationStatus = InvitationStatus.pending
    accepted_account_id: UUID | None = None
    accepted_at: datetime | None = None

    @classmethod
    def create(
        cls,
        *,
        invitation_id: UUID,
        family_id: UUID,
        invited_by: UUID,
        invitee_phone: str,
        role: FamilyMemberRole,
        token_hash: str,
        created_at: datetime | None = None,
    ) -> Invitation:
        created = created_at or datetime.now(UTC)
        return cls(
            id=invitation_id,
            family_id=family_id,
            invited_by=invited_by,
            invitee_phone=normalize_invitee_phone(invitee_phone),
            role=role,
            token_hash=token_hash,
            created_at=created,
            expires_at=created + timedelta(hours=24),
        )

    def invited_event(self) -> FamilyMemberInvited:
        return FamilyMemberInvited(
            invitation_id=self.id,
            family_id=self.family_id,
            invitee_phone=self.invitee_phone,
            role=self.role,
            expires_at=self.expires_at,
        )

    def accept(
        self, account_id: UUID, account_phone: str, now: datetime | None = None
    ) -> FamilyMemberJoined:
        accepted_at = now or datetime.now(UTC)
        if self.status is not InvitationStatus.pending:
            if self.status is InvitationStatus.accepted:
                raise InvitationUsed("invitation can only be accepted once")
            raise InvitationExpired("invitation has expired")
        if accepted_at >= self.expires_at:
            self.status = InvitationStatus.expired
            raise InvitationExpired("invitation has expired")
        if normalize_invitee_phone(account_phone) != self.invitee_phone:
            raise InviteeMismatch("session phone does not match invitation")

        self.status = InvitationStatus.accepted
        self.accepted_account_id = account_id
        self.accepted_at = accepted_at
        return FamilyMemberJoined(
            invitation_id=self.id,
            family_id=self.family_id,
            account_id=account_id,
            role=self.role,
            joined_at=accepted_at,
        )
