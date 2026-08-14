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

    @classmethod
    def start(
        cls,
        *,
        session_id: str,
        call_id: str,
        tool_name: str,
        request_hash: str,
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
        )

    def complete(self, result: dict) -> None:
        self.status = ToolInvocationStatus.completed
        self.result = result

    def require_approval(self, result: dict) -> None:
        self.status = ToolInvocationStatus.approval_required
        self.result = result
