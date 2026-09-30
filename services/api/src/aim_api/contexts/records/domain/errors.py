class RecordsDomainError(Exception):
    """Base error for records domain invariant violations."""


class RecordValidationError(RecordsDomainError):
    """Raised when a record does not satisfy its type-specific payload contract."""


class RecordAccessDenied(RecordsDomainError):
    """Raised when a non-author attempts to mutate a record."""


class RecordNotFound(RecordsDomainError):
    """Raised when a visible record cannot be found."""


class AttachmentRejected(RecordsDomainError):
    """上传的附件类型或大小不合规。kind 用来决定返回 413 还是 415。"""

    def __init__(self, kind: str, message: str) -> None:
        super().__init__(message)
        self.kind = kind


class AttachmentUnavailable(RecordsDomainError):
    """附件不存在、不属于本家庭，或已经挂在别的记录上。"""
