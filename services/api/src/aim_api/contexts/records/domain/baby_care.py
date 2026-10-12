from datetime import UTC, datetime
import math
from typing import Any
from uuid import UUID
from aim_api.contexts.records.domain.errors import RecordValidationError

CARE_TYPES = {"feeding", "diaper", "sleep"}
FEEDING_MODES = {"breast", "expressed", "formula", "mixed", "unknown"}


def baby_id(data: dict) -> UUID:
    value = data.get("baby_id")
    try:
        identifier = UUID(value) if isinstance(value, str) else None
    except (ValueError, TypeError):
        identifier = None
    if identifier is None or str(identifier) != value:
        raise RecordValidationError("请选择这段孕期的宝宝")
    return identifier


def aware(value: datetime) -> None:
    if value.tzinfo is None or value.utcoffset() is None:
        raise RecordValidationError("记录时间需要包含时区")


def ended_at(data: dict) -> datetime:
    value = data.get("ended_at")
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00")) if isinstance(value, str) else None
    except ValueError:
        result = None
    if result is None:
        raise RecordValidationError("请填写睡眠结束时间")
    aware(result)
    return result


def validate_care(kind: str, data: dict, occurred_at: datetime, *, now: datetime | None = None) -> None:
    baby_id(data)
    aware(occurred_at)
    current = now or datetime.now(UTC)
    if occurred_at > current:
        raise RecordValidationError("照护时间不能晚于现在，请核对设备时间")
    if kind == "feeding":
        if set(data) - {"baby_id", "mode", "volume_ml", "duration_minutes", "side"}:
            raise RecordValidationError("喂养记录包含不支持的字段")
        mode = data.get("mode", "unknown")
        if not isinstance(mode, str) or mode not in FEEDING_MODES:
            raise RecordValidationError("喂养方式不支持")
        volume = data.get("volume_ml")
        if volume is not None and (type(volume) not in (int, float) or not math.isfinite(volume) or not 0.1 <= volume <= 2000):
            raise RecordValidationError("已知奶量需为 0.1–2000 毫升的数字；不知道可以不填")
        if mode == "breast" and volume is not None:
            raise RecordValidationError("母乳亲喂不估算毫升数，可记录时长")
        duration = data.get("duration_minutes")
        if duration is not None and (type(duration) is not int or not 1 <= duration <= 180):
            raise RecordValidationError("时长需为 1–180 分钟的整数；不知道可以不填")
        side = data.get("side")
        if side is not None and (not isinstance(side, str) or side not in {"left", "right", "both"} or mode != "breast"):
            raise RecordValidationError("亲喂侧别只用于母乳亲喂")
    elif kind == "diaper":
        if set(data) != {"baby_id", "kind"} or not isinstance(data.get("kind"), str) or data["kind"] not in {"wet", "dirty", "both", "dry"}:
            raise RecordValidationError("请记录尿布是湿、便、都有或干的")
    else:
        if set(data) - {"baby_id", "ended_at", "duration_seconds"}:
            raise RecordValidationError("睡眠记录包含不支持的字段")
        end = ended_at(data)
        if end > current or not 1 <= (end - occurred_at).total_seconds() <= 86400:
            raise RecordValidationError("睡眠结束需晚于开始、不晚于现在，单条最长 24 小时")


def normalize_care(kind: str, data: dict, occurred_at: datetime) -> dict[str, Any]:
    result = {"baby_id": str(baby_id(data))}
    if kind == "feeding":
        result.update({"mode": data.get("mode", "unknown")})
        for key in ("volume_ml", "duration_minutes", "side"):
            if data.get(key) is not None:
                result[key] = data[key]
    elif kind == "diaper":
        result["kind"] = data["kind"]
    else:
        end = ended_at(data)
        result.update({"ended_at": end.astimezone(UTC).isoformat(), "duration_seconds": int((end - occurred_at).total_seconds())})
    return result
