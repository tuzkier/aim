from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from aim_api.contexts.family.domain.errors import InvitationExpired
from aim_api.contexts.family.domain.family import FamilyMemberRole
from aim_api.contexts.family.domain.invitation import Invitation, InvitationStatus

NOW = datetime(2026, 10, 2, tzinfo=UTC)
PHONE = "13800001111"


def _invitation() -> Invitation:
    return Invitation.create(
        invitation_id=uuid4(),
        family_id=uuid4(),
        invited_by=uuid4(),
        invitee_phone=PHONE,
        role=FamilyMemberRole.father,
        token_hash="h",
        created_at=NOW,
    )


def test_lasts_seven_days() -> None:
    invitation = _invitation()
    assert invitation.expires_at == NOW + timedelta(days=7)
    assert invitation.is_open(NOW + timedelta(days=6))
    assert not invitation.is_open(NOW + timedelta(days=7))


def test_declined_can_still_be_accepted_before_it_expires() -> None:
    invitation = _invitation()
    invitation.decline()
    assert invitation.status is InvitationStatus.declined
    assert invitation.is_open(NOW)
    invitation.accept(uuid4(), PHONE, NOW + timedelta(days=1))
    assert invitation.status is InvitationStatus.accepted


def test_revoked_cannot_be_accepted() -> None:
    invitation = _invitation()
    invitation.revoke()
    assert not invitation.is_open(NOW)
    with pytest.raises(InvitationExpired):
        invitation.accept(uuid4(), PHONE, NOW)


def test_only_open_invitations_can_be_declined_or_revoked() -> None:
    invitation = _invitation()
    invitation.accept(uuid4(), PHONE, NOW)
    with pytest.raises(InvitationExpired):
        invitation.decline()
    with pytest.raises(InvitationExpired):
        invitation.revoke()
