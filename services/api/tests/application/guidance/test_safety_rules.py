from __future__ import annotations

import re

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
        "late-bleeding", "early-spotting", "low-fever",
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
    assert weeks["waters-breaking"] == (16, 42)
    assert weeks["late-bleeding"] == (20, 42)
    assert weeks["early-spotting"] == (4, 19)
    assert weeks["urgent-bleeding"] is None


def test_any_bleeding_is_covered_in_every_week():
    """出血不论多少都要有去处：孕早期少量出血当天联系，20 周后出血立即就医。"""
    for week in range(4, 43):
        ids = {rule.id for rule in execute(week=week)}
        assert {"early-spotting", "late-bleeding"} & ids, week


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


def _first_sentence(text: str) -> str:
    return re.split(r"[；。]", text, maxsplit=1)[0]


def test_same_day_actions_do_not_send_people_to_the_emergency_room():
    """same_day 写成立即急诊就成了狼来了，真正紧急的反而没人当回事。
    只看第一句：后面允许写「出现什么情况升为立即就医」的升档线。"""
    for rule in execute():
        if rule.severity == "same_day":
            first = _first_sentence(rule.action)
            assert first.startswith("今天"), rule.id
            assert "120" not in first and "急诊" not in first, rule.id


def test_fetal_movement_count_threshold_starts_at_28_weeks():
    """百科从 28 周起数胎动；24–27 周只按「比平时明显减少」判断，免得误报。"""
    by_id = {rule.id: rule for rule in execute()}
    assert "28 周后 2 小时不足 10 次" in by_id["reduced-fetal-movement"].condition


def test_swelling_carries_the_blood_pressure_escalation_line():
    by_id = {rule.id: rule for rule in execute()}
    action = by_id["sudden-swelling"].action
    assert "160" in action and "110" in action and "立即就医" in action


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
