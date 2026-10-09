#!/usr/bin/env python3
"""清理过期与无主的图片附件。每天由 crontab 跑一次（见 infrastructure/deploy/README.md）。

    docker exec -i aim-api-1 python scripts/purge_orphan_attachments.py
    docker exec -i aim-api-1 python scripts/purge_orphan_attachments.py --dry-run
"""

from __future__ import annotations

import asyncio
import sys
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from aim_api.contexts.records.adapters.outbound.storage import LocalAttachmentStorage  # noqa: E402
from aim_api.contexts.records.application.commands import purge_attachments  # noqa: E402
from aim_api.platform.config.settings import get_settings  # noqa: E402
from aim_api.platform.database.session import create_database  # noqa: E402


async def run(dry_run: bool) -> int:
    settings = get_settings()
    database = create_database(settings.database_url)
    storage = LocalAttachmentStorage(settings.attachments_root)
    try:
        async with database.session() as session:
            summary = await purge_attachments.execute(
                session, storage, now=datetime.now(UTC), dry_run=dry_run
            )
    finally:
        await database.dispose()
    prefix = "[dry-run] " if dry_run else ""
    print(f"{prefix}删除附件记录 {summary.rows_deleted} 条，删除文件 {summary.files_deleted} 个")
    return 0


def main() -> int:
    return asyncio.run(run("--dry-run" in sys.argv[1:]))


if __name__ == "__main__":
    raise SystemExit(main())
