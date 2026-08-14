"""Guard the dependency direction of the DDD service."""

from __future__ import annotations

import ast
from pathlib import Path

SERVICE_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = SERVICE_ROOT / "src" / "aim_api"
CONTEXTS_ROOT = SOURCE_ROOT / "contexts"

FORBIDDEN_DOMAIN_IMPORTS = {
    "fastapi",
    "pydantic",
    "pydantic_settings",
    "sqlalchemy",
}


def _import_root(module: str) -> str:
    return module.split(".", 1)[0]


def test_context_domains_exist_and_remain_framework_free() -> None:
    context_domains = sorted(CONTEXTS_ROOT.glob("*/domain"))
    assert {path.parent.name for path in context_domains} == {
        "agent_access",
        "family",
        "guidance",
        "identity",
        "planning",
        "pregnancy",
    }

    violations: list[str] = []
    for domain_root in context_domains:
        for source_file in domain_root.rglob("*.py"):
            tree = ast.parse(source_file.read_text(encoding="utf-8"), filename=str(source_file))
            for node in ast.walk(tree):
                imported: str | None = None
                if isinstance(node, ast.Import):
                    imported = node.names[0].name
                elif isinstance(node, ast.ImportFrom) and node.module:
                    imported = node.module

                if imported and _import_root(imported) in FORBIDDEN_DOMAIN_IMPORTS:
                    violations.append(f"{source_file}: {imported}")
                if imported and ".adapters" in imported:
                    violations.append(f"{source_file}: cross-layer import {imported}")

    assert violations == []


def test_domain_files_do_not_import_other_context_adapters() -> None:
    violations: list[str] = []
    for source_file in CONTEXTS_ROOT.glob("*/domain/**/*.py"):
        tree = ast.parse(source_file.read_text(encoding="utf-8"), filename=str(source_file))
        for node in ast.walk(tree):
            if not isinstance(node, ast.ImportFrom) or not node.module:
                continue
            if node.module.startswith("aim_api.contexts.") and ".adapters" in node.module:
                violations.append(f"{source_file}: {node.module}")

    assert violations == []
