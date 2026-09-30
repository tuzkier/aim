"""删除缓冲期已过的注销账号。

这是唯一一处跨上下文直接写表的地方。注销要把一个人从家庭、孕期、记录、计划、
对话里同时抹掉，按上下文各自暴露删除接口再逐个调，代价远大于收益；
而且它只跑在定时任务里，不在请求路径上。
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from aim_api.contexts.identity.domain.account import DELETION_GRACE_PERIOD, AccountStatus


@dataclass(frozen=True, slots=True)
class PurgeSummary:
    account_id: UUID
    families_deleted: int
    families_anonymized: int


async def execute(
    session: AsyncSession, *, now: datetime, dry_run: bool = False
) -> list[PurgeSummary]:
    # 截止点必须恰好是 now - DELETION_GRACE_PERIOD：认证那边靠「令牌活不过被删的账号」
    # 这条不变量，它成立的前提就是这里和会话有效期用同一个常量。
    cutoff = now - DELETION_GRACE_PERIOD
    expired = (
        (
            await session.execute(
                text(
                    "SELECT id FROM accounts "
                    "WHERE status = :status AND deletion_requested_at IS NOT NULL "
                    "AND deletion_requested_at <= :cutoff"
                ),
                {"status": AccountStatus.pending_deletion.value, "cutoff": cutoff},
            )
        )
        .scalars()
        .all()
    )

    summaries: list[PurgeSummary] = []
    for account_id in expired:
        summary = await _purge_one(session, UUID(str(account_id)))
        summaries.append(summary)

    if dry_run:
        await session.rollback()
    else:
        await session.commit()
    return summaries


async def _purge_one(session: AsyncSession, account_id: UUID) -> PurgeSummary:
    families_deleted = 0
    families_anonymized = 0

    # 他发出的邀请：invited_by 是 RESTRICT 外键，不删账号删不掉。
    await session.execute(
        text("DELETE FROM family_invitations WHERE invited_by = :id"), {"id": account_id}
    )
    # 别人发给他的邀请按手机号匹配，没有外键，不主动删就会一直留着他的手机号。
    phone = await session.scalar(
        text("SELECT phone FROM accounts WHERE id = :id"), {"id": account_id}
    )
    await session.execute(
        text("DELETE FROM family_invitations WHERE invitee_phone = :phone"), {"phone": phone}
    )
    # AIM 工具调用的结果（tool_invocations.result_json）里有记录、待办这些健康内容，
    # 它只靠 session_id 与 agent_sessions.eve_session_id 关联，没有外键，
    # 得赶在 agent_sessions 随账号 CASCADE 之前删，否则就成了没人认领的孤儿。
    await session.execute(
        text(
            "DELETE FROM tool_invocations WHERE session_id IN "
            "(SELECT eve_session_id FROM agent_sessions WHERE account_id = :id)"
        ),
        {"id": account_id},
    )
    # 他的私密记录：只有作者本人能看，人没了就没人能看，留着无意义。
    # 全家可见的记录属于家庭，跟着家庭走（见下面的分支）。
    # 私密记录上挂的图片同理：行在这里删，磁盘文件由每天的附件清理按「无主文件」扫掉。
    await session.execute(
        text(
            "DELETE FROM attachments WHERE record_id IN (SELECT id FROM records "
            "WHERE author_account_id = :id AND visibility = 'private')"
        ),
        {"id": account_id},
    )
    # 留在家庭里的图片不再指向一个已注销的人。
    await session.execute(
        text("UPDATE attachments SET uploaded_by = NULL WHERE uploaded_by = :id"),
        {"id": account_id},
    )
    await session.execute(
        text("DELETE FROM records WHERE author_account_id = :id AND visibility = 'private'"),
        {"id": account_id},
    )

    family_ids = (
        (
            await session.execute(
                text("SELECT family_id FROM family_members WHERE account_id = :id"),
                {"id": account_id},
            )
        )
        .scalars()
        .all()
    )

    for family_id in family_ids:
        others = (
            (
                await session.execute(
                    text(
                        # 只算已加入的：邀请了但没接受的人是 pending 行，
                        # 既不该挡住整家删除，更不该继承 created_by。
                        "SELECT account_id FROM family_members "
                        "WHERE family_id = :family AND account_id <> :id AND status = 'active' "
                        "ORDER BY joined_at NULLS LAST, invited_at NULLS LAST"
                    ),
                    {"family": family_id, "id": account_id},
                )
            )
            .scalars()
            .all()
        )

        if others:
            await session.execute(
                text(
                    "UPDATE tasks SET assigned_member_id = NULL "
                    "WHERE assigned_member_id = :id AND pregnancy_id IN "
                    "(SELECT id FROM pregnancies WHERE family_id = :family)"
                ),
                {"id": account_id, "family": family_id},
            )
            await session.execute(
                text(
                    "UPDATE families SET created_by = :heir WHERE id = :family AND created_by = :id"
                ),
                {"heir": others[0], "family": family_id, "id": account_id},
            )
            families_anonymized += 1
        else:
            # 唯一成员：整个家庭一起走。顺序按依赖：先叶子表，最后 families。
            await session.execute(
                text(
                    "DELETE FROM task_changes WHERE task_id IN (SELECT id FROM tasks "
                    "WHERE pregnancy_id IN (SELECT id FROM pregnancies WHERE family_id = :family))"
                ),
                {"family": family_id},
            )
            await session.execute(
                text(
                    "DELETE FROM tasks WHERE pregnancy_id IN "
                    "(SELECT id FROM pregnancies WHERE family_id = :family)"
                ),
                {"family": family_id},
            )
            await session.execute(
                text(
                    "DELETE FROM pregnancy_plans WHERE pregnancy_id IN "
                    "(SELECT id FROM pregnancies WHERE family_id = :family)"
                ),
                {"family": family_id},
            )
            # 家庭的图片（含没挂到记录上的）：行在这里删，文件由每天的附件清理扫掉。
            await session.execute(
                text("DELETE FROM attachments WHERE family_id = :family"), {"family": family_id}
            )
            await session.execute(
                text("DELETE FROM records WHERE family_id = :family"), {"family": family_id}
            )
            await session.execute(
                text(
                    "DELETE FROM pregnancy_facts WHERE pregnancy_id IN "
                    "(SELECT id FROM pregnancies WHERE family_id = :family)"
                ),
                {"family": family_id},
            )
            await session.execute(
                text("DELETE FROM pregnancies WHERE family_id = :family"), {"family": family_id}
            )
            await session.execute(
                text("DELETE FROM family_invitations WHERE family_id = :family"),
                {"family": family_id},
            )
            # 家庭里的对话会话可能是早已离开的成员留下的，同样先清它们的工具调用。
            await session.execute(
                text(
                    "DELETE FROM tool_invocations WHERE session_id IN "
                    "(SELECT eve_session_id FROM agent_sessions WHERE family_id = :family)"
                ),
                {"family": family_id},
            )
            await session.execute(
                text("DELETE FROM agent_sessions WHERE family_id = :family"), {"family": family_id}
            )
            await session.execute(
                text("DELETE FROM families WHERE id = :family"), {"family": family_id}
            )
            families_deleted += 1

    # family_members 与 agent_sessions 对 accounts 是 CASCADE，随账号一起删。
    await session.execute(text("DELETE FROM accounts WHERE id = :id"), {"id": account_id})
    return PurgeSummary(
        account_id=account_id,
        families_deleted=families_deleted,
        families_anonymized=families_anonymized,
    )
