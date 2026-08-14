from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from aim_api.contexts.planning.application.ports import FamilyMembershipPort, PregnancyOwnershipPort


@dataclass(frozen=True, slots=True)
class AgentToolContext:
    account_id: UUID
    family_id: UUID
    pregnancy_id: UUID
    session_id: str
    call_id: str


async def authorize_tool(
    context: AgentToolContext,
    family_membership: FamilyMembershipPort,
    pregnancy_ownership: PregnancyOwnershipPort,
) -> None:
    pregnancy = await pregnancy_ownership.get_pregnancy(context.pregnancy_id)
    if pregnancy is None or pregnancy.family_id != context.family_id:
        raise PermissionError("pregnancy does not belong to the session family")
    if not await family_membership.is_active_member(context.family_id, context.account_id):
        raise PermissionError("actor is not an active family member")
