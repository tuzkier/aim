from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from uuid import UUID, uuid4


class ToolInvocationStatus(StrEnum):
    completed = "completed"
    approval_required = "approval_required"
    failed = "failed"


@dataclass(slots=True)
class ToolInvocation:
    operation_id: UUID
    session_id: str
    call_id: str
    tool_name: str
    request_hash: str
    status: ToolInvocationStatus
    result: dict
    created_at: datetime
    #: 这次调用代表谁、作用在哪段孕期。撤销时据此校验归属；历史记录为空。
    account_id: UUID | None = None
    family_id: UUID | None = None
    pregnancy_id: UUID | None = None
    #: 已被撤销的时刻。再次撤销时直接返回成功。
    undone_at: datetime | None = None

    @classmethod
    def start(
        cls,
        *,
        session_id: str,
        call_id: str,
        tool_name: str,
        request_hash: str,
        account_id: UUID | None = None,
        family_id: UUID | None = None,
        pregnancy_id: UUID | None = None,
    ) -> ToolInvocation:
        return cls(
            operation_id=uuid4(),
            session_id=session_id,
            call_id=call_id,
            tool_name=tool_name,
            request_hash=request_hash,
            status=ToolInvocationStatus.completed,
            result={},
            created_at=datetime.now(UTC),
            account_id=account_id,
            family_id=family_id,
            pregnancy_id=pregnancy_id,
        )

    def complete(self, result: dict) -> None:
        self.status = ToolInvocationStatus.completed
        self.result = result

    def require_approval(self, result: dict) -> None:
        self.status = ToolInvocationStatus.approval_required
        self.result = result
