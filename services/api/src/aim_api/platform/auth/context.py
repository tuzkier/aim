from __future__ import annotations

import base64
import hashlib
import hmac
import json
import time
from dataclasses import dataclass
from uuid import UUID

from fastapi import HTTPException, Request, status


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


def issue_session_token(
    account_id: UUID, phone: str, secret: str, *, now: int | None = None
) -> str:
    issued_at = int(time.time()) if now is None else now
    payload = {"account_id": str(account_id), "phone": phone, "exp": issued_at + 3600}
    encoded = _encode(payload)
    signature = hmac.new(secret.encode(), encoded.encode(), hashlib.sha256).hexdigest()
    return f"aim.v1.{encoded}.{signature}"


def authenticate(request: Request) -> ActorContext:
    authorization = request.headers.get("authorization", "")
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="missing session token"
        )

    token = authorization.removeprefix("Bearer ")
    parts = token.split(".")
    if len(parts) != 4 or parts[0:2] != ["aim", "v1"]:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid session token"
        )

    settings = request.app.state.settings
    encoded, provided_signature = parts[2], parts[3]
    expected_signature = hmac.new(
        settings.auth_secret.encode(), encoded.encode(), hashlib.sha256
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
