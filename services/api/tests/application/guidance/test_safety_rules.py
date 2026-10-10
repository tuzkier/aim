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


def test_rules_cover_the_key_red_flags():
    ids = {rule.id for rule in execute()}
    assert {
        "urgent-bleeding", "ectopic-signs", "waters-breaking", "reduced-fetal-movement",
        "preterm-contractions", "preeclampsia-signs", "seizure", "chest-pain-breathing",
        "leg-clot", "high-fever", "self-harm-thoughts", "sudden-swelling",
        "itching-palms-soles", "urinary-infection", "severe-vomiting", "persistent-low-mood",
    } <= ids


def test_severity_uses_the_three_levels():
    assert {rule.severity for rule in execute()} <= {"urgent", "same_day", "routine"}


def test_week_filter_keeps_whole_pregnancy_rules_and_matching_ranges():
    early = {rule.id for rule in execute(week=8)}
    late = {rule.id for rule in execute(week=34)}
    assert "ectopic-signs" in early and "ectopic-signs" not in late
    assert "preterm-contractions" in late and "preterm-contractions" not in early
    assert "urgent-bleeding" in early and "urgent-bleeding" in late


def test_week_ranges_follow_the_spec():
    """只在特定孕周出现的信号，范围按规格写死——改动要过医学复核。"""
    weeks = {rule.id: rule.weeks for rule in execute()}
    assert weeks["ectopic-signs"] == (4, 13)
    assert weeks["preterm-contractions"] == (20, 36)
    assert weeks["reduced-fetal-movement"] == (24, 42)
    assert weeks["waters-breaking"] == (20, 42)
    assert weeks["urgent-bleeding"] is None


def test_week_range_bounds_are_inclusive():
    by_id = {rule.id: rule for rule in execute()}
    ectopic = by_id["ectopic-signs"]
    assert ectopic.applies(4) and ectopic.applies(13)
    assert not ectopic.applies(3) and not ectopic.applies(14)
    assert by_id["high-fever"].applies(0) and by_id["high-fever"].applies(45)


def test_conditions_are_short_plain_language():
    """孕妇要能一眼看懂并自己对照，condition 控制在 40 字以内。"""
    too_long = [rule.id for rule in execute() if len(rule.condition) > 40]
    assert too_long == []


def test_same_day_actions_do_not_send_people_to_the_emergency_room():
    """same_day 写成立即急诊就成了狼来了，真正紧急的反而没人当回事。"""
    for rule in execute():
        if rule.severity == "same_day":
            assert rule.action.startswith("今天"), rule.id
            assert "120" not in rule.action and "急诊" not in rule.action, rule.id


def test_urgent_actions_say_go_now():
    for rule in execute():
        if rule.severity == "urgent":
            assert "立即" in rule.action, rule.id


def test_self_harm_action_includes_the_national_hotline():
    by_id = {rule.id: rule for rule in execute()}
    assert "12356" in by_id["self-harm-thoughts"].action


def test_high_fever_threshold_is_38_5():
    by_id = {rule.id: rule for rule in execute()}
    assert "38.5" in by_id["high-fever"].condition
