from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from enum import StrEnum
from uuid import UUID

from aim_api.contexts.family.domain.errors import (
    DuplicateFamilyMember,
    FamilyAccessDenied,
    FamilyMemberNotFound,
)


class FamilyMemberRole(StrEnum):
    mother = "mother"
    father = "father"
    other_caregiver = "other_caregiver"


class FamilyMemberStatus(StrEnum):
    pending = "pending"
    active = "active"


@dataclass(slots=True)
class FamilyMember:
    account_id: UUID
    role: FamilyMemberRole
    status: FamilyMemberStatus
    joined_at: datetime | None = None
    invited_at: datetime | None = None

    @classmethod
    def active(
        cls,
        account_id: UUID,
        role: FamilyMemberRole,
        *,
        joined_at: datetime | None = None,
    ) -> FamilyMember:
        return cls(
            account_id=account_id,
            role=role,
            status=FamilyMemberStatus.active,
            joined_at=joined_at or datetime.now(UTC),
        )

    @classmethod
    def pending(
        cls,
        account_id: UUID,
        role: FamilyMemberRole,
        *,
        invited_at: datetime | None = None,
    ) -> FamilyMember:
        return cls(
            account_id=account_id,
            role=role,
            status=FamilyMemberStatus.pending,
            invited_at=invited_at or datetime.now(UTC),
        )


@dataclass(slots=True)
class Family:
    id: UUID
    name: str
    created_by: UUID
    created_at: datetime
    members: dict[UUID, FamilyMember] = field(default_factory=dict)

    @classmethod
    def create(
        cls,
        family_id: UUID,
        name: str,
        created_by: UUID,
        created_at: datetime | None = None,
    ) -> Family:
        cleaned_name = name.strip()
        if not cleaned_name:
            raise ValueError("family name cannot be empty")
        return cls(
            id=family_id,
            name=cleaned_name,
            created_by=created_by,
            created_at=created_at or datetime.now(UTC),
        )

    def add_member(self, member: FamilyMember) -> None:
        if member.account_id in self.members:
            raise DuplicateFamilyMember("account already belongs to this family")
        self.members[member.account_id] = member

    def active_member(self, account_id: UUID) -> FamilyMember:
        member = self.members.get(account_id)
        if member is None or member.status is not FamilyMemberStatus.active:
            raise FamilyAccessDenied("account is not an active family member")
        return member

    def member(self, account_id: UUID) -> FamilyMember:
        try:
            return self.members[account_id]
        except KeyError as error:
            raise FamilyMemberNotFound("family member does not exist") from error

    def activate_member(self, account_id: UUID, now: datetime | None = None) -> FamilyMember:
        member = self.member(account_id)
        if member.status is FamilyMemberStatus.active:
            raise DuplicateFamilyMember("account already belongs to this family")
        member.status = FamilyMemberStatus.active
        member.joined_at = now or datetime.now(UTC)
        return member
