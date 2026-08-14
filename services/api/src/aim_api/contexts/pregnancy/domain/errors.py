from __future__ import annotations


class PregnancyDomainError(Exception):
    code = "pregnancy.domain_error"


class PregnancyAccessDenied(PregnancyDomainError):
    code = "pregnancy.access_denied"


class PregnancyNotFound(PregnancyDomainError):
    code = "pregnancy.not_found"
