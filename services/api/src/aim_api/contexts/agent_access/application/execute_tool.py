from __future__ import annotations

import hashlib
import json
from typing import Any


def effective_request_hash(tool_name: str, payload: dict[str, Any]) -> str:
    """Hash only tool inputs; identity headers and model-supplied scope IDs are excluded."""

    effective = {
        key: value
        for key, value in payload.items()
        if key not in {"family_id", "pregnancy_id", "account_id"}
    }
    encoded = json.dumps(
        {"tool": tool_name, "payload": effective},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    )
    return hashlib.sha256(encoded.encode()).hexdigest()
