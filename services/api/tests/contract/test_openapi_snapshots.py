from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]


def test_public_and_agent_contracts_have_separate_path_sets() -> None:
    public = json.loads((ROOT / "contracts/public-api/openapi.json").read_text(encoding="utf-8"))
    agent = json.loads((ROOT / "contracts/agent-tools/openapi.json").read_text(encoding="utf-8"))
    public_paths = set(public["paths"])
    agent_paths = set(agent["paths"])

    assert public_paths
    assert agent_paths
    assert all(path.startswith("/api/") for path in public_paths)
    assert all(path.startswith("/internal/") for path in agent_paths)
    assert public_paths.isdisjoint(agent_paths)


def test_public_contract_includes_authenticated_record_operations() -> None:
    public = json.loads((ROOT / "contracts/public-api/openapi.json").read_text(encoding="utf-8"))
    collection = "/api/v1/pregnancies/{pregnancy_id}/records"
    item = "/api/v1/pregnancies/{pregnancy_id}/records/{record_id}"

    assert {"get", "post"}.issubset(public["paths"][collection])
    assert {"get", "patch", "delete"}.issubset(public["paths"][item])
