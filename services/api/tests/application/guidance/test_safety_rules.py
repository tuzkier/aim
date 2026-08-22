from __future__ import annotations

from aim_api.contexts.guidance.application.queries.get_safety_rules import execute


class TestSafetyRules:
    """危险信号是安全兜底。内容早就写在 content/safety-rules 里，
    但此前没有任何代码读取它——App 里完全看不到。"""

    def test_returns_the_red_flags_from_the_content_library(self):
        rules = execute()

        assert rules, "内容库里有红线规则，不该返回空"
        ids = {rule.id for rule in rules}
        assert "urgent-bleeding" in ids

    def test_each_rule_carries_condition_action_and_severity(self):
        rules = execute()
        bleeding = next(rule for rule in rules if rule.id == "urgent-bleeding")

        assert "出血" in bleeding.condition
        assert bleeding.action
        assert bleeding.severity == "urgent"

    def test_urgent_rules_come_first(self):
        """最紧急的排在最前——用户扫一眼就该看到最要命的那条。"""
        rules = execute()
        severities = [rule.severity for rule in rules]
        urgent_positions = [i for i, s in enumerate(severities) if s == "urgent"]
        other_positions = [i for i, s in enumerate(severities) if s != "urgent"]

        if urgent_positions and other_positions:
            assert max(urgent_positions) < min(other_positions)

    def test_rules_carry_provenance(self):
        """医疗内容必须能追溯来源，这是 ADR-0008 的安全基线要求。"""
        rules = execute()

        assert all(rule.source for rule in rules)
        assert all(rule.source_url for rule in rules)
        assert all(rule.reviewed_at for rule in rules)
