"""家庭动态里「人」和「孕期」相关的事。

待办和记录的动态直接从各自的表里取；成员进出和改预产期没有别的地方留痕，记在这里。
成员事件在 payload 里存当时的称呼：人走了之后，动态里仍能说清是谁。
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any
from uuid import UUID, uuid4


class FamilyEventKind(StrEnum):
    member_joined = "member_joined"
    member_left = "member_left"
    member_removed = "member_removed"
    due_date_changed = "due_date_changed"
    birth_recorded = "birth_recorded"
    birth_date_changed = "birth_date_changed"
    birth_retracted = "birth_retracted"


@dataclass(frozen=True, slots=True)
class FamilyEvent:
    id: UUID
    family_id: UUID
    kind: FamilyEventKind
    actor_account_id: UUID | None
    subject_account_id: UUID | None
    created_at: datetime
    payload: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def new(
        cls,
        family_id: UUID,
        kind: FamilyEventKind,
        *,
        actor: UUID | None,
        subject: UUID | None = None,
        payload: dict[str, Any] | None = None,
        now: datetime | None = None,
    ) -> FamilyEvent:
        return cls(
            id=uuid4(),
            family_id=family_id,
            kind=kind,
            actor_account_id=actor,
            subject_account_id=subject,
            created_at=now or datetime.now(UTC),
            payload=dict(payload or {}),
        )
