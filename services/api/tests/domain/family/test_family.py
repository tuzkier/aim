from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from aim_api.contexts.family.domain.errors import (
    DuplicateFamilyMember,
    InvitationExpired,
    InvitationUsed,
    InviteeMismatch,
)
from aim_api.contexts.family.domain.family import (
    Family,
    FamilyMember,
    FamilyMemberRole,
    FamilyMemberStatus,
)
from aim_api.contexts.family.domain.invitation import Invitation
from aim_api.contexts.identity.domain.account import Account


def test_account_does_not_carry_family_role() -> None:
    account = Account.register(uuid4(), "+8613800138000")

    assert not hasattr(account, "role")
    assert {role.value for role in FamilyMemberRole} == {
        "mother",
        "father",
        "other_caregiver",
    }


def test_same_account_cannot_join_family_twice() -> None:
    account_id = uuid4()
    family = Family.create(uuid4(), "我们的家", account_id, datetime.now(UTC))
    family.add_member(FamilyMember.active(account_id, FamilyMemberRole.mother))

    with pytest.raises(DuplicateFamilyMember):
        family.add_member(FamilyMember.active(account_id, FamilyMemberRole.father))


def test_invitation_expires_after_7_days_and_can_only_be_used_once() -> None:
    now = datetime(2026, 8, 14, 10, tzinfo=UTC)
    invitation = Invitation.create(
        invitation_id=uuid4(),
        family_id=uuid4(),
        invited_by=uuid4(),
        invitee_phone="13800138000",
        role=FamilyMemberRole.father,
        token_hash="hash",
        created_at=now,
    )

    assert invitation.expires_at == now + timedelta(days=7)
    joined = invitation.accept(uuid4(), "13800138000", now + timedelta(hours=1))
    assert joined.invitation_id == invitation.id
    assert invitation.status.value == "accepted"

    with pytest.raises(InvitationUsed):
        invitation.accept(uuid4(), "13800138000", now + timedelta(hours=2))

    expired = Invitation.create(
        invitation_id=uuid4(),
        family_id=uuid4(),
        invited_by=uuid4(),
        invitee_phone="13800138000",
        role=FamilyMemberRole.other_caregiver,
        token_hash="hash-2",
        created_at=now,
    )
    with pytest.raises(InvitationExpired):
        expired.accept(uuid4(), "13800138000", now + timedelta(days=7, seconds=1))


def test_invitation_requires_the_invited_phone_and_activates_pending_member() -> None:
    now = datetime.now(UTC)
    invitation = Invitation.create(
        invitation_id=uuid4(),
        family_id=uuid4(),
        invited_by=uuid4(),
        invitee_phone="13800138000",
        role=FamilyMemberRole.other_caregiver,
        token_hash="hash",
        created_at=now,
    )
    with pytest.raises(InviteeMismatch):
        invitation.accept(uuid4(), "13900139000", now)

    family = Family.create(uuid4(), "我们的家", uuid4(), now)
    member = FamilyMember.pending(uuid4(), FamilyMemberRole.other_caregiver)
    family.add_member(member)
    assert member.status is FamilyMemberStatus.pending
    family.activate_member(member.account_id, now)
    assert member.status is FamilyMemberStatus.active
