"""密码哈希。

用 argon2id 而不是 bcrypt：bcrypt 在 72 字节处静默截断，超长密码会被无声削弱，
而用户和调用方都得不到任何提示。

长度是密码强度里真正起作用的维度，所以这里只管长度，不要求大小写数字符号的组合。
组合规则逼出来的是 `Passw0rd!` 这类可预测密码（NIST SP 800-63B 同此结论）。
"""

from __future__ import annotations

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

MIN_PASSWORD_LENGTH = 8

_hasher = PasswordHasher()


class PasswordTooShort(ValueError):
    """密码短于 MIN_PASSWORD_LENGTH。"""


def hash_password(raw: str) -> str:
    if len(raw) < MIN_PASSWORD_LENGTH:
        raise PasswordTooShort(f"password must be at least {MIN_PASSWORD_LENGTH} characters")
    return _hasher.hash(raw)


def verify_password(raw: str, hashed: str) -> bool:
    """密码对不对。

    任何形式的失败都返回 False，包括哈希本身非法——库里若因迁移事故存进了坏数据，
    应当是登录失败，而不是抛异常变成 500 并把内部细节漏给调用方。
    """
    try:
        return _hasher.verify(hashed, raw)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False
