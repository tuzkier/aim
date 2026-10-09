"""成员进出家庭时的跨表清理。

一个账号始终恰好属于一个家庭：离开（退出或被移出）后立刻给他建一个空家庭；
接受邀请时，原家庭必须「没有内容」，随后整个删掉。

这几张表之间没有外键（records、tasks 等按模块各自建表），所以和注销清理一样按依赖手写 SQL。
注销清理的「唯一成员」分支也调用这里的 `delete_family`。
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from aim_api.contexts.family.adapters.outbound.persistence.repositories import (
    SqlAlchemyFamilyRepository,
)
from aim_api.contexts.family.domain.family import Family, FamilyMember, FamilyMemberRole

_IN_FAMILY_PREGNANCIES = "(SELECT id FROM pregnancies WHERE family_id = :family)"

_BLOCKED = "你的家庭里已经有{what}，不能直接加入。可以请对方换一个没用过的手机号邀请你。"


async def family_has_content(session: AsyncSession, family_id: UUID, account_id: UUID) -> str | None:
    """原家庭是否「有内容」。没有返回 None；有则返回给用户看的原因。

    没有内容 = 只有本人一个在籍成员；没有记录（含已删除的）、孕期信息、图片；
    待办全部来自初始计划，且都没有被改动过。
    """

    async def count(sql: str) -> int:
        return int(await session.scalar(text(sql), {"family": family_id, "id": account_id}) or 0)

    if await count(
        "SELECT count(*) FROM family_members WHERE family_id = :family "
        "AND account_id <> :id AND status = 'active'"
    ):
        return _BLOCKED.format(what="其他成员")
    if await count("SELECT count(*) FROM records WHERE family_id = :family"):
        return _BLOCKED.format(what="记录")
    if await count(
        f"SELECT count(*) FROM pregnancy_facts WHERE pregnancy_id IN {_IN_FAMILY_PREGNANCIES}"
    ):
        return _BLOCKED.format(what="孕期信息")
    if await count("SELECT count(*) FROM attachments WHERE family_id = :family"):
        return _BLOCKED.format(what="图片")
    if await count(
        f"SELECT count(*) FROM tasks WHERE pregnancy_id IN {_IN_FAMILY_PREGNANCIES} "
        "AND (source_type <> 'template' OR id IN (SELECT task_id FROM task_changes))"
    ):
        return _BLOCKED.format(what="待办")
    return None


async def delete_family(session: AsyncSession, family_id: UUID) -> None:
    """整个家庭连同其数据一起删除。顺序按依赖：先叶子表，最后 families。

    图片只删行，磁盘文件由每天的附件清理按「无主文件」扫掉。
    """
    params = {"family": family_id}
    statements = [
        "DELETE FROM task_changes WHERE task_id IN (SELECT id FROM tasks "
        f"WHERE pregnancy_id IN {_IN_FAMILY_PREGNANCIES})",
        f"DELETE FROM tasks WHERE pregnancy_id IN {_IN_FAMILY_PREGNANCIES}",
        f"DELETE FROM pregnancy_plans WHERE pregnancy_id IN {_IN_FAMILY_PREGNANCIES}",
        "DELETE FROM attachments WHERE family_id = :family",
        "DELETE FROM records WHERE family_id = :family",
        f"DELETE FROM pregnancy_facts WHERE pregnancy_id IN {_IN_FAMILY_PREGNANCIES}",
        "DELETE FROM pregnancies WHERE family_id = :family",
        "DELETE FROM family_invitations WHERE family_id = :family",
        "DELETE FROM family_events WHERE family_id = :family",
        # 家庭里的对话会话可能是早已离开的成员留下的，同样先清它们的工具调用。
        "DELETE FROM tool_invocations WHERE session_id IN "
        "(SELECT eve_session_id FROM agent_sessions WHERE family_id = :family)",
        "DELETE FROM agent_sessions WHERE family_id = :family",
        "DELETE FROM family_members WHERE family_id = :family",
        "DELETE FROM families WHERE id = :family",
    ]
    for statement in statements:
        await session.execute(text(statement), params)


async def detach_member(session: AsyncSession, family_id: UUID, account_id: UUID) -> None:
    """一个人离开家庭（退出或被移出）。调用方负责确认家里还有别人。

    - 指派给他的待办改为未指派；
    - 他在这个家庭里的私密记录（及其图片）删除——人走了就没人能看；
    - 全家可见的记录留给家里人；
    - 他是管理员时，转给最早加入的在籍成员。
    """
    params = {"family": family_id, "id": account_id}
    await session.execute(
        text(
            "UPDATE tasks SET assigned_member_id = NULL WHERE assigned_member_id = :id "
            f"AND pregnancy_id IN {_IN_FAMILY_PREGNANCIES}"
        ),
        params,
    )
    private_records = (
        "(SELECT id FROM records WHERE family_id = :family "
        "AND author_account_id = :id AND visibility = 'private')"
    )
    await session.execute(
        text(f"DELETE FROM attachments WHERE record_id IN {private_records}"), params
    )
    await session.execute(
        text(
            "DELETE FROM records WHERE family_id = :family "
            "AND author_account_id = :id AND visibility = 'private'"
        ),
        params,
    )
    await session.execute(
        text("DELETE FROM family_members WHERE family_id = :family AND account_id = :id"), params
    )
    heir = await session.scalar(
        text(
            "SELECT account_id FROM family_members WHERE family_id = :family AND status = 'active' "
            "ORDER BY joined_at NULLS LAST, account_id LIMIT 1"
        ),
        params,
    )
    if heir is not None:
        await session.execute(
            text("UPDATE families SET created_by = :heir WHERE id = :family AND created_by = :id"),
            {**params, "heir": heir},
        )


async def create_empty_family(
    session: AsyncSession,
    account_id: UUID,
    role: FamilyMemberRole,
    nickname: str | None,
) -> UUID:
    """给离开家庭的人一个新的空家庭（没有孕期），保持「每个账号都有一个家庭」。"""
    now = datetime.now(UTC)
    repository = SqlAlchemyFamilyRepository(session)
    family = Family.create(uuid4(), "我的家庭", account_id, now)
    await repository.add_family(family)
    await repository.add_member(
        family.id, FamilyMember.active(account_id, role, nickname=nickname, joined_at=now)
    )
    return family.id
