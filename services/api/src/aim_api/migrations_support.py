"""迁移与运行时共用的常量。

放在这里而不是迁移文件里，是为了让测试能引用同一个值——测试 import 迁移模块
要绕 alembic 的加载方式，而一个被复制两份的常量迟早会对不上。
"""

from __future__ import annotations

#: 存量账号回填用的占位。argon2 无法解析它，`verify_password` 因此恒为 False，
#: 账号被锁住直到用 scripts/reset_password.py 显式设一个密码。
UNUSABLE_PASSWORD_MARKER = "!"
