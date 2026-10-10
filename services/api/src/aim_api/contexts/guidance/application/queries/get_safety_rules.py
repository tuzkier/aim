from __future__ import annotations

import yaml

from aim_api.contexts.guidance.application.queries.get_guidance import CONTENT_ROOT
from aim_api.contexts.guidance.domain.safety_rule import SafetyRule


def execute(week: int | None = None) -> tuple[SafetyRule, ...]:
    """读取危险信号。按紧急程度排序，最要命的排最前。

    传入 week 时只保留该孕周适用的条目；不传返回全部（旧版 App 依赖这一点）。
    """
    content_dir = CONTENT_ROOT / "safety-rules"
    if not content_dir.is_dir():
        return ()
    rules: list[SafetyRule] = []
    for path in sorted(content_dir.glob("*.yaml")):
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        rules.extend(SafetyRule.from_document(document, item) for item in document["items"])
    if week is not None:
        rules = [rule for rule in rules if rule.applies(week)]
    return tuple(sorted(rules, key=lambda rule: (rule.severity_rank, rule.id)))
