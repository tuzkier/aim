from __future__ import annotations


class FamilyDomainError(Exception):
    code = "family.domain_error"


class DuplicateFamilyMember(FamilyDomainError):
    code = "family.duplicate_member"


class FamilyMemberNotFound(FamilyDomainError):
    code = "family.member_not_found"


class FamilyAccessDenied(FamilyDomainError):
    code = "family.access_denied"


class InvitationExpired(FamilyDomainError):
    code = "family.invitation_expired"


class InvitationUsed(FamilyDomainError):
    code = "family.invitation_used"


class InviteeMismatch(FamilyDomainError):
    code = "family.invitee_mismatch"


class InvitationNotFound(FamilyDomainError):
    code = "family.invitation_not_found"
