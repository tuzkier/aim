class RecordsDomainError(Exception):
    """Base error for records domain invariant violations."""


class RecordValidationError(RecordsDomainError):
    """Raised when a record does not satisfy its type-specific payload contract."""


class RecordAccessDenied(RecordsDomainError):
    """Raised when a non-author attempts to mutate a record."""
