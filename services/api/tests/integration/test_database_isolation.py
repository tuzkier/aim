"""守门用例：测试永远不许跑在开发库上。

这不是在测业务逻辑，是在测「测试自己」。开发库曾因为集成测试直连而攒下
961 个账号，其中 784 个是后端测试造的——每个用例造一个随机手机号，跑完
既不回滚也不清理。conftest 的一次性库如果哪天失效、或者有人把它去掉，
这条会立刻红，而不是等到某天发现开发库又胀了。
"""

from __future__ import annotations

from aim_api.platform.config.settings import get_settings


def _database_name(url: str) -> str:
    return url.rsplit("/", 1)[-1].split("?", 1)[0]


def test_tests_run_against_a_disposable_database() -> None:
    name = _database_name(get_settings().database_url)

    assert name.startswith("aim_test_"), (
        f"测试连到了 {name!r}。集成测试只能跑在 conftest 建的一次性库上，"
        "连开发库会把随机手机号永久写进去。"
    )
