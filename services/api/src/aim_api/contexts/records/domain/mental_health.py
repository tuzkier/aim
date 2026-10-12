"""情绪记录校验与 EPDS 确定性计分；不是诊断，也不调用模型。"""
from typing import Any

from aim_api.contexts.records.domain.errors import RecordValidationError

EPDS_VERSION = "epds-nsw-zh-Hans-2023-v1"
EPDS_PERIODS = {"pregnancy_late", "postpartum_2w", "postpartum_6w", "manual"}
MOOD_TAGS = {"sleep", "worry", "energy", "support", "other"}


def epds_result(answers: Any) -> dict[str, Any]:
    if not isinstance(answers, list) or len(answers) != 10 or any(
        type(value) is not int or not 0 <= value <= 3 for value in answers
    ):
        raise RecordValidationError("自评需要完整填写十题，每题选择一个选项")
    points = [value if i in (0, 1, 3) else 3 - value for i, value in enumerate(answers)]
    score = sum(points)
    level = "immediate" if points[9] > 0 else "assessment" if score >= 13 else "follow_up" if score >= 10 else "support"
    return {"score": score, "item_10": points[9], "support_level": level}


def validate_mood(data: dict[str, Any], content: str | None) -> None:
    if set(data) - {"mood", "tags"}:
        raise RecordValidationError("心情记录只包含心情与标签")
    if type(data.get("mood")) is not int or not 1 <= data["mood"] <= 5:
        raise RecordValidationError("心情请选 1–5 档")
    tags = data.get("tags", [])
    if not isinstance(tags, list) or len(tags) > 5 or any(
        not isinstance(tag, str) or tag not in MOOD_TAGS for tag in tags
    ) or len(set(tags)) != len(tags):
        raise RecordValidationError("心情标签不支持或重复")
    if content is not None and len(content) > 500:
        raise RecordValidationError("心情备注最多 500 字")


def validate_epds(data: dict[str, Any]) -> None:
    if data.get("version") != EPDS_VERSION:
        raise RecordValidationError("自评版本不支持，请更新 App")
    period = data.get("period", "manual")
    if not isinstance(period, str) or period not in EPDS_PERIODS:
        raise RecordValidationError("自评时间节点不支持")
    epds_result(data.get("answers"))
