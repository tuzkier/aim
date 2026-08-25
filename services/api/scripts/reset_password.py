#!/usr/bin/env python3
"""重置某个手机号的密码。

没有短信也没有邮箱，自助找回在技术上不成立，所以这是唯一的找回路径。
刻意做成命令行工具而不是接口：任何「无需身份即可改密码」的 HTTP 端点，
本身就是一个绕过密码的通道。

用法：

    docker exec -i aim-api-1 python scripts/reset_password.py 13800000000 新密码

密码从命令行参数传入会留在 shell 历史里。想避免就省略第二个参数，
脚本会以不回显的方式提示输入。
"""

from __future__ import annotations

import asyncio
import getpass
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from sqlalchemy import select  # noqa: E402

from aim_api.contexts.family.adapters.outbound.persistence.models import (  # noqa: E402
    AccountModel,
)
from aim_api.platform.auth.passwords import (  # noqa: E402
    MIN_PASSWORD_LENGTH,
    PasswordTooShort,
    hash_password,
)
from aim_api.platform.config.settings import get_settings  # noqa: E402
from aim_api.platform.database.session import create_database  # noqa: E402


async def reset(phone: str, password: str) -> int:
    database = create_database(get_settings().database_url)
    async with database.session() as session:
        account = await session.scalar(select(AccountModel).where(AccountModel.phone == phone))
        if account is None:
            print(f"没有找到手机号 {phone} 的账号", file=sys.stderr)
            return 1
        account.password_hash = hash_password(password)
        await session.commit()
    print(f"已重置 {phone} 的密码")
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2

    phone = sys.argv[1]
    if len(sys.argv) >= 3:
        password = sys.argv[2]
    else:
        password = getpass.getpass("新密码（不回显）：")
        if password != getpass.getpass("再输一次："):
            print("两次输入不一致", file=sys.stderr)
            return 1

    try:
        # 在这里先校验，而不是等写库时才失败——失败得越早，越不会留下半截状态。
        hash_password(password)
    except PasswordTooShort:
        print(f"密码至少要 {MIN_PASSWORD_LENGTH} 位", file=sys.stderr)
        return 1

    return asyncio.run(reset(phone, password))


if __name__ == "__main__":
    raise SystemExit(main())
