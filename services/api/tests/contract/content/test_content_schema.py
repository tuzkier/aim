from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[5]


def _validate(schema_path: Path, document_path: Path) -> None:
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    document = yaml.safe_load(document_path.read_text(encoding="utf-8"))
    errors = sorted(
        Draft202012Validator(schema).iter_errors(document), key=lambda error: error.path
    )
    assert errors == [], "\n".join(error.message for error in errors)


@pytest.mark.parametrize(
    "document_path",
    sorted((Path(__file__).resolve().parents[5] / "content/pregnancy-tasks").glob("*.yaml")),
)
def test_pregnancy_task_content_has_version_and_applicability(document_path: Path) -> None:
    root = Path(__file__).resolve().parents[5]
    _validate(
        root / "content/pregnancy-tasks/schema.json",
        document_path,
    )


def test_safety_and_hangzhou_content_have_source_and_review_date() -> None:
    _validate(
        ROOT / "content/safety-rules/schema.json",
        ROOT / "content/safety-rules/pregnancy-red-flags.yaml",
    )
    _validate(
        ROOT / "content/hangzhou/schema.json",
        ROOT / "content/hangzhou/pregnancy-benefits.yaml",
    )
