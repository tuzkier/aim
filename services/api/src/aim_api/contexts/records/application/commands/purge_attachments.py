"""清理不再需要的图片附件。

三类：没挂到任何记录、上传超过 90 天的；所挂记录已删除超过 30 天的（记录是软删除，
30 天内撤销还能连图一起回来）；数据库里已经没有对应行的孤儿文件（注销清理只删行，
文件在这里统一扫掉）。孤儿文件只删修改时间超过 1 小时的，避免误删正在上传的图。
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from aim_api.contexts.records.application.ports import AttachmentStoragePort

ORPHAN_RETENTION = timedelta(days=90)
DELETED_RECORD_RETENTION = timedelta(days=30)
STRAY_FILE_GRACE = timedelta(hours=1)


@dataclass(frozen=True, slots=True)
class PurgeAttachmentsSummary:
    rows_deleted: int
    files_deleted: int


async def execute(
    session: AsyncSession,
    storage: AttachmentStoragePort,
    *,
    now: datetime,
    dry_run: bool = False,
) -> PurgeAttachmentsSummary:
    expired = [
        UUID(str(value))
        for value in (
            await session.execute(
                text(
                    "SELECT a.id FROM attachments a "
                    "LEFT JOIN records r ON r.id = a.record_id "
                    "WHERE (a.record_id IS NULL AND a.created_at < :orphan_cutoff) "
                    "OR (r.deleted_at IS NOT NULL AND r.deleted_at < :deleted_cutoff)"
                ),
                {
                    "orphan_cutoff": now - ORPHAN_RETENTION,
                    "deleted_cutoff": now - DELETED_RECORD_RETENTION,
                },
            )
        ).scalars()
    ]
    known = {
        UUID(str(value))
        for value in (await session.execute(text("SELECT id FROM attachments"))).scalars()
    }
    grace_cutoff = (now - STRAY_FILE_GRACE).timestamp()
    stray = [
        attachment_id
        for attachment_id, modified_at in storage.list_files()
        if attachment_id not in known and modified_at < grace_cutoff
    ]
    summary = PurgeAttachmentsSummary(
        rows_deleted=len(expired), files_deleted=len(expired) + len(stray)
    )
    if dry_run:
        await session.rollback()
        return summary

    if expired:
        await session.execute(text("DELETE FROM attachments WHERE id = ANY(:ids)"), {"ids": expired})
    await session.commit()
    # 先提交删行再删文件：删文件失败只会留下孤儿文件，下次再扫；反过来会留下指向空文件的行。
    for attachment_id in [*expired, *stray]:
        storage.delete(attachment_id)
    return summary
