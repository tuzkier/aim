"""每次 pytest 跑在一个用完即弃的数据库上。

在此之前，集成测试直接连开发库：`create_app()` 走 `get_settings()`，
`DATABASE_URL` 指向哪个库就写哪个库。每个用例造一个随机手机号（为了避免撞号），
跑完既不回滚也不清理，于是每跑一轮 `make test` 就往开发库里永久留下几十行。
开发库里因此攒了 961 个账号、755 个孕期，其中 784 个来自后端测试。

两个后果：打开 App 看到的是测试造的数据；测试之间也不隔离，上一轮的残留会
成为下一轮的隐含前提。

现在 session 开始时新建一个 `aim_test_<随机>` 库、跑完迁移，结束时删掉。
无论开发者把 `DATABASE_URL` 指到哪，测试都碰不到那个库。
"""

from __future__ import annotations

import os
import uuid
from collections.abc import Iterator
from urllib.parse import urlsplit, urlunsplit

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text

from aim_api.platform.config.settings import get_settings

API_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#: 本机 5432 上的 Homebrew postgres 没有 `aim` 角色，连不上；Compose 栈映射在 55434。
#: 所以默认值取 Compose 那个，而不是 Settings 里那个连不通的 localhost:5432。
DEFAULT_SOURCE_URL = "postgresql+asyncpg://aim:aim@127.0.0.1:55434/aim"


def _with_database(url: str, name: str) -> str:
    return urlunsplit(urlsplit(url)._replace(path=f"/{name}"))


def _to_sync(url: str) -> str:
    """建库/删库要用同步驱动，asyncpg 不能跑在 AUTOCOMMIT 的裸连接上。"""
    if "+asyncpg" in url:
        return url.replace("+asyncpg", "+psycopg", 1)
    if url.startswith("postgresql://"):
        return url.replace("postgresql://", "postgresql+psycopg://", 1)
    return url


@pytest.fixture(scope="session", autouse=True)
def disposable_database() -> Iterator[str]:
    source = os.environ.get("DATABASE_URL") or DEFAULT_SOURCE_URL
    name = f"aim_test_{uuid.uuid4().hex[:12]}"
    test_url = _with_database(source, name)

    # 连维护库才能 CREATE/DROP DATABASE——不能在要建的那个库里建它自己。
    admin = create_engine(_to_sync(_with_database(source, "postgres")), isolation_level="AUTOCOMMIT")
    with admin.connect() as conn:
        conn.execute(text(f'CREATE DATABASE "{name}"'))

    previous = os.environ.get("DATABASE_URL")
    os.environ["DATABASE_URL"] = test_url
    # Settings 是 lru_cache(maxsize=1)，不清缓存的话迁移和 App 都会用旧地址。
    get_settings.cache_clear()

    try:
        config = Config(os.path.join(API_ROOT, "alembic.ini"))
        config.set_main_option("script_location", os.path.join(API_ROOT, "migrations"))
        command.upgrade(config, "head")
        yield test_url
    finally:
        if previous is None:
            os.environ.pop("DATABASE_URL", None)
        else:
            os.environ["DATABASE_URL"] = previous
        get_settings.cache_clear()

        with admin.connect() as conn:
            # 引擎池里可能还留着连接，不断开就 DROP 不掉。
            conn.execute(
                text(
                    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
                    "WHERE datname = :name AND pid <> pg_backend_pid()"
                ),
                {"name": name},
            )
            conn.execute(text(f'DROP DATABASE IF EXISTS "{name}"'))
        admin.dispose()


@pytest.fixture(scope="session", autouse=True)
def attachments_root(tmp_path_factory) -> Iterator[str]:
    """测试上传的图片写进临时目录，不落到开发机的 var/attachments。"""
    root = tmp_path_factory.mktemp("attachments")
    previous = os.environ.get("AIM_ATTACHMENTS_ROOT")
    os.environ["AIM_ATTACHMENTS_ROOT"] = str(root)
    get_settings.cache_clear()
    try:
        yield str(root)
    finally:
        if previous is None:
            os.environ.pop("AIM_ATTACHMENTS_ROOT", None)
        else:
            os.environ["AIM_ATTACHMENTS_ROOT"] = previous
        get_settings.cache_clear()
