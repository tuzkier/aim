from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
from dataclasses import dataclass
from uuid import UUID

from fastapi import HTTPException, Request, status
from sqlalchemy import text


def _encode(payload: dict[str, object]) -> str:
    raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _decode(value: str) -> dict[str, object]:
    padded = value + "=" * (-len(value) % 4)
    raw = base64.urlsafe_b64decode(padded.encode())
    result = json.loads(raw)
    if not isinstance(result, dict):
        raise ValueError("token payload must be an object")
    return result


@dataclass(frozen=True, slots=True)
class ActorContext:
    account_id: UUID
    phone: str
    expires_at: int


#: 会话有效期。原来是 1 小时——免密登录时代重登一次即可，没有代价；
#: 加了密码之后它意味着每小时手输一次密码。孕期 App 是每天要用的工具，不是网银。
SESSION_TTL_SECONDS = 30 * 24 * 3600


def issue_session_token(
    account_id: UUID, phone: str, secret: str, *, now: int | None = None
) -> str:
    issued_at = int(time.time()) if now is None else now
    payload = {"account_id": str(account_id), "phone": phone, "exp": issued_at + SESSION_TTL_SECONDS}
    encoded = _encode(payload)
    signature = hmac.new(secret.encode(), encoded.encode(), hashlib.sha256).hexdigest()
    return f"aim.v1.{encoded}.{signature}"


def authenticate(request: Request) -> ActorContext:
    authorization = request.headers.get("authorization", "")
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="missing session token"
        )

    settings = request.app.state.settings
    return verify_session_token(authorization.removeprefix("Bearer "), settings.auth_secret)


def verify_session_token(token: str, secret: str) -> ActorContext:
    """校验一张会话票，成立就返回它代表的身份。

    从 `authenticate` 里抽出来，是因为 agent 运行时的 scope 解析也要验它，
    而那条路上没有 FastAPI `Request`。
    """
    parts = token.split(".")
    if len(parts) != 4 or parts[0:2] != ["aim", "v1"]:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid session token"
        )

    encoded, provided_signature = parts[2], parts[3]
    expected_signature = hmac.new(
        secret.encode(), encoded.encode(), hashlib.sha256
    ).hexdigest()
    if not hmac.compare_digest(provided_signature, expected_signature):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid session token"
        )

    try:
        payload = _decode(encoded)
        account_id = UUID(str(payload["account_id"]))
        phone = str(payload["phone"])
        expires_at = int(payload["exp"])
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid session token"
        ) from error
    if expires_at <= int(time.time()):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="session token expired"
        )
    return ActorContext(account_id=account_id, phone=phone, expires_at=expires_at)


async def ensure_account_active(database: object, account_id: UUID) -> None:
    """票是无状态签名，注销账号的旧票在 30 天内仍然验得过。

    所以验签之后再按主键查一次状态。用一句 SQL 而不是 import 家庭上下文的模型：
    platform 不该依赖某个 context 的持久化层。
    """
    async with database.session() as session:  # type: ignore[attr-defined]
        status_value = await session.scalar(
            text("SELECT status FROM accounts WHERE id = :id"), {"id": account_id}
        )
    # 查不到行的票放行：`POST /api/v1/families` 至今仍会为一张合法签名的票
    # 按需建账号（免密时代留下的路径，集成测试大量依赖它）。这里只拦
    # 「存在但不是 active」的账号——停用和注销缓冲期——那才是这层检查要堵的洞。
    if status_value is not None and status_value != "active":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="account is not active"
        )


async def authenticate_active(request: Request) -> ActorContext:
    actor = authenticate(request)
    await ensure_account_active(request.app.state.database, actor.account_id)
    return actor
