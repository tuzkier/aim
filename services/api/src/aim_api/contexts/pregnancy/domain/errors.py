from __future__ import annotations


class PregnancyDomainError(Exception):
    code = "pregnancy.domain_error"


class PregnancyAccessDenied(PregnancyDomainError):
    code = "pregnancy.access_denied"


class PregnancyNotFound(PregnancyDomainError):
    code = "pregnancy.not_found"


class DueDateOutOfRange(PregnancyDomainError):
    """换算出的当前孕周不在 0 周 0 天到 42 周 0 天之间。message 是给用户看的中文。"""

    code = "pregnancy.due_date_out_of_range"
