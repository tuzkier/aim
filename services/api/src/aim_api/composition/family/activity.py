"""家庭动态：把几张表里「谁做了什么」合并成一条按时间倒序的时间线。

来源：
- 新建的待办（不含初始计划的模板待办，否则建档时会刷出十几条）；
- 完成待办（task_changes 里的 complete）；
- 全家可见记录的新建（私密记录不出现）；
- family_events：成员加入、退出、被移出，改预产期。

每个来源各取 `limit` 条再合并，保证合并后的前 `limit` 条正确。
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

_IN_FAMILY_PREGNANCIES = "(SELECT id FROM pregnancies WHERE family_id = :family)"

_RECORD_TYPE_NAMES = {
    "symptom": "身体感受",
    "checkup": "产检",
    "note": "备忘",
    "question": "问题",
    "checklist": "清单",
    "knowledge": "知识",
    "fetal_movement": "胎动",
    "contraction": "宫缩",
    "hospital_trip": "去医院",
    "mood": "心情",
    "epds": "情绪自评",
}

FORMER_MEMBER = "已离开的成员"

_FAR_FUTURE = datetime(9999, 12, 31, tzinfo=UTC)


@dataclass(frozen=True, slots=True)
class ActivityItem:
    id: str
    kind: str
    actor_name: str
    #: 句子里动词后面的那部分：待办标题、记录标题、新预产期、被移出的人。
    title: str
    target_type: str | None
    target_id: UUID | None
    target_deleted: bool
    via_agent: bool
    created_at: datetime


def _month_day(value: str) -> str:
    day = date.fromisoformat(value)
    return f"{day.month}月{day.day}日"


async def family_activity(
    session: AsyncSession,
    family_id: UUID,
    member_names: dict[UUID, str],
    *,
    before: datetime | None,
    limit: int,
) -> list[ActivityItem]:
    params = {"family": family_id, "before": before or _FAR_FUTURE, "limit": limit}
    since = "AND created_at < :before ORDER BY created_at DESC LIMIT :limit"

    def name(account_id: UUID | None, fallback: str | None = None) -> str:
        if account_id is not None and account_id in member_names:
            return member_names[account_id]
        return fallback or FORMER_MEMBER

    items: list[ActivityItem] = []

    for row in await session.execute(
        text(
            "SELECT id, title, created_at, created_by_actor_type, created_by_actor_id FROM tasks "
            f"WHERE pregnancy_id IN {_IN_FAMILY_PREGNANCIES} AND source_type <> 'template' {since}"
        ),
        params,
    ):
        items.append(
            ActivityItem(
                id=f"task_created:{row.id}",
                kind="task_created",
                actor_name=name(row.created_by_actor_id),
                title=row.title,
                target_type="task",
                target_id=row.id,
                target_deleted=False,
                via_agent=row.created_by_actor_type == "agent",
                created_at=row.created_at,
            )
        )

    for row in await session.execute(
        text(
            "SELECT tc.id, t.id AS task_id, t.title, tc.created_at, tc.changed_by_actor_id "
            "FROM task_changes tc JOIN tasks t ON t.id = tc.task_id "
            f"WHERE t.pregnancy_id IN {_IN_FAMILY_PREGNANCIES} AND tc.operation = 'complete' "
            "AND tc.created_at < :before ORDER BY tc.created_at DESC LIMIT :limit"
        ),
        params,
    ):
        items.append(
            ActivityItem(
                id=f"task_completed:{row.id}",
                kind="task_completed",
                actor_name=name(row.changed_by_actor_id),
                title=row.title,
                target_type="task",
                target_id=row.task_id,
                target_deleted=False,
                via_agent=False,
                created_at=row.created_at,
            )
        )

    for row in await session.execute(
        text(
            "SELECT id, title, record_type, author_account_id, created_at, deleted_at FROM records "
            f"WHERE family_id = :family AND visibility = 'family' {since}"
        ),
        params,
    ):
        items.append(
            ActivityItem(
                id=f"record_created:{row.id}",
                kind="record_created",
                actor_name=name(row.author_account_id),
                title=row.title or _RECORD_TYPE_NAMES.get(row.record_type, "记录"),
                target_type="record",
                target_id=row.id,
                target_deleted=row.deleted_at is not None,
                via_agent=False,
                created_at=row.created_at,
            )
        )

    for row in await session.execute(
        text(
            "SELECT id, kind, actor_account_id, subject_account_id, payload, created_at "
            f"FROM family_events WHERE family_id = :family {since}"
        ),
        params,
    ):
        payload = row.payload or {}
        stored_name = payload.get("display_name")
        if row.kind == "due_date_changed":
            actor, title = name(row.actor_account_id), _month_day(payload["to"])
        elif row.kind in ("birth_recorded", "birth_date_changed", "birth_retracted"):
            actor, title = name(row.actor_account_id), _month_day(payload.get("to") or payload["date"])
        elif row.kind == "member_removed":
            actor, title = name(row.actor_account_id), stored_name or "一位家人"
        else:
            # 加入、退出：主语就是这个人本身，人走了也能用当时的称呼。
            actor, title = name(row.subject_account_id, stored_name), ""
        items.append(
            ActivityItem(
                id=f"{row.kind}:{row.id}",
                kind=row.kind,
                actor_name=actor,
                title=title,
                target_type=None,
                target_id=None,
                target_deleted=False,
                via_agent=False,
                created_at=row.created_at,
            )
        )

    items.sort(key=lambda item: item.created_at, reverse=True)
    return items[:limit]
