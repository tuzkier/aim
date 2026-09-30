from __future__ import annotations

import asyncio
import os
from datetime import UTC, datetime, timedelta
from uuid import uuid4

from sqlalchemy import text

from aim_api.contexts.records.adapters.outbound.storage import LocalAttachmentStorage
from aim_api.contexts.records.application.commands import purge_attachments
from aim_api.platform.config.settings import get_settings
from aim_api.platform.database.session import create_database

NOW = datetime(2026, 12, 1, tzinfo=UTC)


async def _seed(session, *, attachment_id, created_at, record_id=None):
    await session.execute(
        text(
            "INSERT INTO attachments (id, family_id, pregnancy_id, uploaded_by, media_type, "
            "byte_size, record_id, created_at) VALUES (:id, :f, :p, NULL, 'image/jpeg', 10, :r, :c)"
        ),
        {"id": attachment_id, "f": uuid4(), "p": uuid4(), "r": record_id, "c": created_at},
    )


async def _seed_record(session, *, record_id, deleted_at):
    await session.execute(
        text(
            "INSERT INTO records (id, pregnancy_id, family_id, author_account_id, record_type, "
            "occurred_at, visibility, structured_data, attachment_refs, created_at, updated_at, "
            "deleted_at) VALUES (:id, :p, :f, :a, 'note', :t, 'family', '{}', '[]', :t, :t, :d)"
        ),
        {"id": record_id, "p": uuid4(), "f": uuid4(), "a": uuid4(), "t": NOW, "d": deleted_at},
    )


def test_purges_old_orphans_long_deleted_records_and_stray_files(tmp_path) -> None:
    storage = LocalAttachmentStorage(tmp_path)
    old_orphan, fresh_orphan, on_deleted, on_recently_deleted, on_live = (
        uuid4() for _ in range(5)
    )
    stray, fresh_stray = uuid4(), uuid4()
    long_deleted_record, recently_deleted_record, live_record = uuid4(), uuid4(), uuid4()

    async def run():
        database = create_database(get_settings().database_url)
        try:
            async with database.session() as session:
                await _seed_record(
                    session, record_id=long_deleted_record, deleted_at=NOW - timedelta(days=31)
                )
                await _seed_record(
                    session, record_id=recently_deleted_record, deleted_at=NOW - timedelta(days=5)
                )
                await _seed_record(session, record_id=live_record, deleted_at=None)
                await _seed(session, attachment_id=old_orphan, created_at=NOW - timedelta(days=91))
                await _seed(session, attachment_id=fresh_orphan, created_at=NOW - timedelta(days=10))
                await _seed(
                    session,
                    attachment_id=on_deleted,
                    created_at=NOW - timedelta(days=40),
                    record_id=long_deleted_record,
                )
                await _seed(
                    session,
                    attachment_id=on_recently_deleted,
                    created_at=NOW - timedelta(days=40),
                    record_id=recently_deleted_record,
                )
                await _seed(
                    session,
                    attachment_id=on_live,
                    created_at=NOW - timedelta(days=200),
                    record_id=live_record,
                )
                await session.commit()
            for attachment_id in (
                old_orphan, fresh_orphan, on_deleted, on_recently_deleted, on_live, stray, fresh_stray
            ):
                storage.save(attachment_id, b"x")
            # 孤儿文件只删「一小时前」的：fresh_stray 的修改时间就是现在，可能正在上传。
            old = (NOW - timedelta(days=2)).timestamp()
            os.utime(storage._path(stray), (old, old))
            os.utime(storage._path(fresh_stray), (NOW.timestamp(), NOW.timestamp()))

            async with database.session() as session:
                summary = await purge_attachments.execute(session, storage, now=NOW)
            async with database.session() as session:
                rows = {
                    value
                    for value in (
                        await session.execute(
                            text("SELECT id FROM attachments WHERE id = ANY(:ids)"),
                            {
                                "ids": [
                                    old_orphan,
                                    fresh_orphan,
                                    on_deleted,
                                    on_recently_deleted,
                                    on_live,
                                ]
                            },
                        )
                    ).scalars()
                }
            return summary, rows
        finally:
            await database.dispose()

    summary, rows = asyncio.run(run())
    remaining = {attachment_id for attachment_id, _ in storage.list_files()}
    assert remaining == {fresh_orphan, on_recently_deleted, on_live, fresh_stray}
    assert rows == {fresh_orphan, on_recently_deleted, on_live}
    assert summary.rows_deleted == 2
    assert summary.files_deleted == 3


def test_dry_run_changes_nothing(tmp_path) -> None:
    storage = LocalAttachmentStorage(tmp_path)
    orphan = uuid4()

    async def run():
        database = create_database(get_settings().database_url)
        try:
            async with database.session() as session:
                await _seed(session, attachment_id=orphan, created_at=NOW - timedelta(days=91))
                await session.commit()
            storage.save(orphan, b"x")
            async with database.session() as session:
                return await purge_attachments.execute(session, storage, now=NOW, dry_run=True)
        finally:
            await database.dispose()

    summary = asyncio.run(run())
    assert summary.rows_deleted >= 1
    assert orphan in {attachment_id for attachment_id, _ in storage.list_files()}
