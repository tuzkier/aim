"""迁移必须能处理已有数据的库。

第一版写成 `ADD COLUMN password_hash TEXT NOT NULL`，在生产上恰好能过——那个库是空的——
但在有 961 个存量账号的开发库上直接失败。「库是空的」不该是一个迁移的前提。

存量账号是免密登录时代建的，从来没有过密码。回填一个永远无法通过校验的值，
它们就被锁住直到显式重置——没有凭证的账号不该能登录。
"""

from __future__ import annotations

from aim_api.migrations_support import UNUSABLE_PASSWORD_MARKER
from aim_api.platform.auth.passwords import verify_password


def test_the_backfilled_value_can_never_authenticate() -> None:
    for attempt in ("", "!", UNUSABLE_PASSWORD_MARKER, "password", "a-good-password"):
        assert not verify_password(attempt, UNUSABLE_PASSWORD_MARKER)
