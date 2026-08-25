from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from uuid import UUID


class AccountStatus(StrEnum):
    active = "active"
    disabled = "disabled"


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
