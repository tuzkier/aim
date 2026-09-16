#!/usr/bin/env python3
"""删除注销缓冲期已过（30 天）的账号。

每天由 crontab 跑一次（见 infrastructure/deploy/README.md）：

    docker exec -i aim-api-1 python scripts/purge_deleted_accounts.py
    docker exec -i aim-api-1 python scripts/purge_deleted_accounts.py --dry-run

`--dry-run` 只打印会删哪些账号，不写库。
"""

from __future__ import annotations

import asyncio
import sys
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from aim_api.contexts.identity.application.commands import purge_expired_deletions  # noqa: E402
from aim_api.platform.config.settings import get_settings  # noqa: E402
from aim_api.platform.database.session import create_database  # noqa: E402


async def run(dry_run: bool) -> int:
    database = create_database(get_settings().database_url)
    async with database.session() as session:
        summaries = await purge_expired_deletions.execute(
            session, now=datetime.now(UTC), dry_run=dry_run
        )
    prefix = "[dry-run] " if dry_run else ""
    if not summaries:
        print(f"{prefix}没有到期的注销账号")
        return 0
    for item in summaries:
        print(
            f"{prefix}账号 {item.account_id}：删除家庭 {item.families_deleted} 个，"
            f"匿名保留家庭 {item.families_anonymized} 个"
        )
    return 0


def main() -> int:
    dry_run = "--dry-run" in sys.argv[1:]
    return asyncio.run(run(dry_run))


if __name__ == "__main__":
    raise SystemExit(main())
