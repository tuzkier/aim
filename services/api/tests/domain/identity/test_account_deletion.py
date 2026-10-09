from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import uuid4

from aim_api.contexts.identity.domain.account import (
    DELETION_GRACE_PERIOD,
    Account,
    AccountStatus,
)

NOW = datetime(2026, 9, 16, 10, 0, tzinfo=UTC)


def _account() -> Account:
    return Account.register(uuid4(), "13800000000", password_hash="x", now=NOW)


def test_request_deletion_marks_pending_and_records_time() -> None:
    account = _account()
    account.request_deletion(now=NOW)
    assert account.status is AccountStatus.pending_deletion
    assert account.deletion_requested_at == NOW


def test_request_deletion_is_idempotent_and_keeps_first_timestamp() -> None:
    account = _account()
    account.request_deletion(now=NOW)
    account.request_deletion(now=NOW + timedelta(days=3))
    assert account.deletion_requested_at == NOW


def test_cancel_deletion_restores_active() -> None:
    account = _account()
    account.request_deletion(now=NOW)
    account.cancel_deletion()
    assert account.status is AccountStatus.active
    assert account.deletion_requested_at is None


def test_grace_period_is_thirty_days() -> None:
    assert DELETION_GRACE_PERIOD == timedelta(days=30)
    account = _account()
    account.request_deletion(now=NOW)
    assert not account.deletion_is_expired(now=NOW + timedelta(days=29, hours=23))
    assert account.deletion_is_expired(now=NOW + DELETION_GRACE_PERIOD)


def test_can_log_in_only_when_active_or_within_grace() -> None:
    active = _account()
    assert active.can_log_in(now=NOW)

    pending = _account()
    pending.request_deletion(now=NOW)
    assert pending.can_log_in(now=NOW + timedelta(days=10))
    assert not pending.can_log_in(now=NOW + timedelta(days=31))

    disabled = _account()
    disabled.status = AccountStatus.disabled
    assert not disabled.can_log_in(now=NOW)
