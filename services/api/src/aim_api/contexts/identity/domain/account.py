from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from uuid import UUID


class AccountStatus(StrEnum):
    active = "active"
    disabled = "disabled"
    #: 用户申请了注销。缓冲期内登录即撤销；到期由清理脚本真正删除。
    pending_deletion = "pending_deletion"


#: 注销缓冲期。App Store 要求 App 内能发起注销，但不要求立即删除；
#: 留 30 天给误操作和「删了才想起来资料还在里面」。
DELETION_GRACE_PERIOD = timedelta(days=30)


def normalize_phone(phone: str) -> str:
    value = phone.strip().replace(" ", "").replace("-", "")
    if value.startswith("+86"):
        value = value[3:]
    if not re.fullmatch(r"[0-9]{6,20}", value):
        raise ValueError("phone must contain 6 to 20 digits")
    return value


@dataclass(slots=True)
class Account:
    """An account is an identity; family roles live on FamilyMember instead."""

    id: UUID
    phone: str
    #: argon2id 哈希。域模型里从不出现明文密码。
    password_hash: str = ""
    status: AccountStatus = AccountStatus.active
    created_at: datetime | None = None
    deletion_requested_at: datetime | None = None

    @classmethod
    def register(
        cls,
        account_id: UUID,
        phone: str,
        *,
        password_hash: str = "",
        now: datetime | None = None,
    ) -> Account:
        return cls(
            id=account_id,
            phone=normalize_phone(phone),
            password_hash=password_hash,
            created_at=now or datetime.now(UTC),
        )

    def ensure_active(self) -> None:
        if self.status is not AccountStatus.active:
            raise ValueError("disabled account cannot perform family operations")

    def request_deletion(self, *, now: datetime) -> None:
        # 重复申请不刷新时间：否则用户每点一次，30 天就重新起算。
        if self.status is AccountStatus.pending_deletion:
            return
        self.status = AccountStatus.pending_deletion
        self.deletion_requested_at = now

    def cancel_deletion(self) -> None:
        self.status = AccountStatus.active
        self.deletion_requested_at = None

    def deletion_is_expired(self, *, now: datetime) -> bool:
        if self.status is not AccountStatus.pending_deletion or self.deletion_requested_at is None:
            return False
        return now >= self.deletion_requested_at + DELETION_GRACE_PERIOD

    def can_log_in(self, *, now: datetime) -> bool:
        if self.status is AccountStatus.active:
            return True
        if self.status is AccountStatus.pending_deletion:
            return not self.deletion_is_expired(now=now)
        return False
