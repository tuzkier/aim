from __future__ import annotations

import pytest

from aim_api.platform.auth.passwords import (
    MIN_PASSWORD_LENGTH,
    PasswordTooShort,
    hash_password,
    verify_password,
)


def test_hash_is_not_the_password_itself() -> None:
    hashed = hash_password("correct horse battery")
    assert "correct horse battery" not in hashed
    assert hashed.startswith("$argon2id$")


def test_verify_accepts_the_right_password() -> None:
    assert verify_password("correct horse battery", hash_password("correct horse battery"))


def test_verify_rejects_the_wrong_password() -> None:
    assert not verify_password("wrong", hash_password("correct horse battery"))


def test_same_password_hashes_differently_each_time() -> None:
    # 加盐的意义：两个用同样密码的账号，拖库时不能一眼看出是同一个密码。
    assert hash_password("same-password") != hash_password("same-password")


def test_short_passwords_are_rejected() -> None:
    with pytest.raises(PasswordTooShort):
        hash_password("a" * (MIN_PASSWORD_LENGTH - 1))


def test_long_passwords_are_not_truncated() -> None:
    # bcrypt 在 72 字节处静默截断，两个只在 72 字节之后不同的密码会互相通过。
    # argon2 不会。这条钉住选型理由。
    base = "x" * 80
    assert not verify_password(base + "DIFFERENT", hash_password(base + "ORIGINAL"))


def test_a_garbage_hash_does_not_blow_up() -> None:
    # 库里若因迁移事故存进了非法哈希，登录应当失败，而不是抛异常变成 500。
    assert not verify_password("anything", "not-a-real-hash")
