from __future__ import annotations

import json
from pathlib import Path

from aim_api.main import app


SERVICE_ROOT = Path(__file__).resolve().parents[1]
WORKSPACE_ROOT = SERVICE_ROOT.parent.parent


def write_contract(path: Path, schema: dict, prefix: str) -> None:
    filtered = dict(schema)
    filtered["paths"] = {
        route: value for route, value in schema.get("paths", {}).items() if route.startswith(prefix)
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(filtered, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


public_schema = app.openapi()
write_contract(WORKSPACE_ROOT / "contracts/public-api/openapi.json", public_schema, "/api/")

for route in app.routes:
    if getattr(route, "path", "").startswith("/internal/"):
        route.include_in_schema = True
app.openapi_schema = None
internal_schema = app.openapi()
write_contract(WORKSPACE_ROOT / "contracts/agent-tools/openapi.json", internal_schema, "/internal/")
