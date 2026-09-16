from __future__ import annotations

from aim_api.contexts.identity.domain.account import DELETION_GRACE_PERIOD
from aim_api.platform.auth.context import SESSION_TTL_SECONDS


def test_session_ttl_never_outlives_deletion_grace_period() -> None:
    """`ensure_account_active` 对「查不到账号行」放行，前提是没有票能活过自己账号的清理。

    每张票都签发在注销申请之前，所以只要有效期不超过缓冲期，票一定先于清理过期。
    改任一常量让这条不成立，就得先回去改 `ensure_account_active`。
    """
    assert SESSION_TTL_SECONDS <= int(DELETION_GRACE_PERIOD.total_seconds())
