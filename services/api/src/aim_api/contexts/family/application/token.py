from __future__ import annotations

import hashlib


def hash_invitation_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()
