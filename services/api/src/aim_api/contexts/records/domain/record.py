from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any, ClassVar
from uuid import UUID

from aim_api.contexts.records.domain.attachment import MAX_ATTACHMENTS_PER_RECORD
from aim_api.contexts.records.domain.contraction import contraction_summary
from aim_api.contexts.records.domain.mental_health import epds_result, validate_epds, validate_mood
from aim_api.contexts.records.domain.baby_care import CARE_TYPES, validate_care, normalize_care
from aim_api.contexts.records.domain.errors import RecordAccessDenied, RecordValidationError


class RecordType(StrEnum):
    symptom = "symptom"
    checkup = "checkup"
    note = "note"
    question = "question"
    checklist = "checklist"
    knowledge = "knowledge"
    fetal_movement = "fetal_movement"
    memory = "memory"
    contraction = "contraction"
    hospital_trip = "hospital_trip"
    mood = "mood"
    epds = "epds"
    feeding = "feeding"
    diaper = "diaper"
    sleep = "sleep"


class RecordVisibility(StrEnum):
    family = "family"
    private = "private"


@dataclass(slots=True)
class Record:
    id: UUID
    pregnancy_id: UUID
    family_id: UUID
    author_account_id: UUID
    record_type: RecordType
    occurred_at: datetime
    visibility: RecordVisibility
    title: str | None
    content: str | None
    structured_data: dict[str, Any]
    attachment_refs: list[str]
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None

    @classmethod
    def create(
        cls,
        *,
        record_id: UUID,
        pregnancy_id: UUID,
        family_id: UUID,
        author_account_id: UUID,
        record_type: RecordType,
        occurred_at: datetime,
        visibility: RecordVisibility,
        structured_data: dict[str, Any],
        title: str | None = None,
        content: str | None = None,
        attachment_refs: list[str] | None = None,
        now: datetime | None = None,
    ) -> Record:
        if not isinstance(structured_data, dict):
            raise RecordValidationError("structured_data must be a JSON object")
        _validate_attachment_refs(attachment_refs or [])
        cls.assert_visibility_allowed(record_type, visibility)
        cls._validate_payload(record_type, structured_data, content, title, occurred_at=occurred_at)
        structured_data = cls._with_defaults(record_type, structured_data, occurred_at=occurred_at)
        if record_type is RecordType.memory:
            title = structured_data["text"][:40]
        created_at = now or datetime.now(UTC)
        return cls(
            id=record_id,
            pregnancy_id=pregnancy_id,
            family_id=family_id,
            author_account_id=author_account_id,
            record_type=record_type,
            occurred_at=occurred_at,
            visibility=visibility,
            title=title,
            content=content,
            structured_data=dict(structured_data),
            attachment_refs=list(attachment_refs or []),
            created_at=created_at,
            updated_at=created_at,
            deleted_at=None,
        )

    def assert_can_mutate(self, account_id: UUID) -> None:
        if self.record_type in (RecordType.mood, RecordType.epds) and self.author_account_id != account_id:
            raise RecordAccessDenied("只有本人可以修改或删除情绪记录")
        # 家庭可见的记录属于整个家庭，家里任何成员都能改（成员资格由命令层先校验）；
        # 仅自己可见的只有作者能改。
        if self.visibility is RecordVisibility.family:
            return
        if self.author_account_id != account_id:
            raise RecordAccessDenied("only the record author can mutate a private record")

    def assert_attachment_refs_valid(self) -> None:
        _validate_attachment_refs(self.attachment_refs)

    def is_visible_to(self, account_id: UUID) -> bool:
        return self.deleted_at is None and (
            self.visibility is RecordVisibility.family or self.author_account_id == account_id
        )

    def soft_delete(self, account_id: UUID, *, now: datetime | None = None) -> None:
        self.assert_can_mutate(account_id)
        deleted_at = now or datetime.now(UTC)
        self.deleted_at = deleted_at
        self.updated_at = deleted_at

    # 可计算的产检指标。范围刻意放宽——只挡明显的输入错误，
    # 不替医生判断什么算异常。
    CHECKUP_METRIC_RANGES: ClassVar[dict[str, tuple[float, float]]] = {
        "weight_kg": (30.0, 200.0),
        "systolic": (60.0, 250.0),
        "diastolic": (30.0, 150.0),
        "fasting_glucose": (2.0, 20.0),
        "hemoglobin": (50.0, 200.0),
        "fetal_heart_rate": (100.0, 200.0),
        "fundal_height_cm": (10.0, 45.0),
    }

    # 产检报告里没有专门字段的化验项，按报告原样记名称和结果。
    # 标记只表达报告上的箭头/异常提示，不做判断。
    OTHER_ITEM_FLAGS: ClassVar[frozenset[str]] = frozenset({"high", "low", "abnormal"})
    MAX_OTHER_ITEMS: ClassVar[int] = 60

    KNOWLEDGE_CATEGORIES: ClassVar[frozenset[str]] = frozenset(
        {"nutrition", "paperwork", "preparation", "checkups", "symptoms", "questions"}
    )
    # 孕期饮食大量情况是「可以但要限量」。只给能/不能两档会逼出错误的
    # 绝对化结论，所以是三档。
    FOOD_VERDICTS: ClassVar[frozenset[str]] = frozenset({"safe", "limit", "avoid"})

    # 胎动计数用「数到 10 次」法。目标写进每条记录，将来换方法时旧数据仍可解读。
    FETAL_MOVEMENT_TARGET: ClassVar[int] = 10
    # 2 小时内不足 10 次需要尽快就医；记录最长 3 小时，超出说明客户端计时出了问题。
    FETAL_MOVEMENT_WINDOW_SECONDS: ClassVar[int] = 2 * 60 * 60
    FETAL_MOVEMENT_MAX_SECONDS: ClassVar[int] = 3 * 60 * 60
    FETAL_MOVEMENT_OUTCOMES: ClassVar[frozenset[str]] = frozenset({"reached", "under", "stopped"})

    @classmethod
    def _validate_fetal_movement(cls, data: dict[str, Any]) -> None:
        def integer(field: str, low: int, high: int) -> int:
            value = data.get(field)
            if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
                raise RecordValidationError(
                    f"fetal movement {field} must be an integer in {low}-{high}"
                )
            return value

        count = integer("count", 0, 200)
        duration = integer("duration_seconds", 0, cls.FETAL_MOVEMENT_MAX_SECONDS)
        target = data.get("target")
        if isinstance(target, bool) or target != cls.FETAL_MOVEMENT_TARGET:
            raise RecordValidationError(
                f"fetal movement target must be {cls.FETAL_MOVEMENT_TARGET}"
            )

        outcome = data.get("outcome")
        if outcome not in cls.FETAL_MOVEMENT_OUTCOMES:
            raise RecordValidationError("fetal movement outcome must be reached, under or stopped")
        if outcome == "reached" and count < target:
            raise RecordValidationError("a reached fetal movement count needs at least the target")
        # 第 10 次点按的秒数向上取整，7199.x 秒记为 7200，所以上限含 7200。
        if outcome == "reached" and duration > cls.FETAL_MOVEMENT_WINDOW_SECONDS:
            raise RecordValidationError(
                "a reached fetal movement count must reach the target within two hours"
            )
        if outcome == "under" and (
            count >= target or duration < cls.FETAL_MOVEMENT_WINDOW_SECONDS
        ):
            raise RecordValidationError(
                "an under fetal movement count needs fewer than the target over two full hours"
            )

        taps = data.get("taps")
        if not isinstance(taps, list) or len(taps) != count:
            raise RecordValidationError("fetal movement taps must list one offset per count")
        previous = 0
        for offset in taps:
            # 秒级取整后相邻两次可能相等，所以是「不递减」而不是「严格递增」。
            if (
                isinstance(offset, bool)
                or not isinstance(offset, int)
                or not previous <= offset <= duration
            ):
                raise RecordValidationError(
                    "fetal movement taps must be non-decreasing seconds within the duration"
                )
            previous = offset

        # 计数中用户点了「胎动明显少了？」：这是要留档的就医信号，与结果无关。
        if "reported_less" in data and not isinstance(data["reported_less"], bool):
            raise RecordValidationError("fetal movement reported_less must be a boolean")

    # 宫缩计时：一次计时最多 500 次、跨度 24 小时；单次宫缩最长 10 分钟，再长说明忘了按结束。
    CONTRACTION_MAX_ITEMS: ClassVar[int] = 500
    CONTRACTION_MAX_START: ClassVar[int] = 24 * 60 * 60
    CONTRACTION_MAX_DURATION: ClassVar[int] = 10 * 60

    @classmethod
    def _validate_contraction(cls, data: dict[str, Any]) -> None:
        # summary 由服务端算，客户端带来的直接忽略；其他字段一律不收。
        if set(data) - {"contractions", "summary"}:
            raise RecordValidationError("contraction records only accept contractions")
        items = data.get("contractions")
        if not isinstance(items, list) or not 1 <= len(items) <= cls.CONTRACTION_MAX_ITEMS:
            raise RecordValidationError(
                f"contractions must list 1-{cls.CONTRACTION_MAX_ITEMS} entries"
            )
        previous_end = 0
        for index, item in enumerate(items):
            if not isinstance(item, dict) or set(item) != {"start", "duration"}:
                raise RecordValidationError("each contraction needs exactly start and duration")
            start, duration = item["start"], item["duration"]
            for value in (start, duration):
                if isinstance(value, bool) or not isinstance(value, int):
                    raise RecordValidationError("contraction start and duration must be integers")
            if index == 0 and start != 0:
                raise RecordValidationError("the first contraction must start at 0")
            if not 0 <= start <= cls.CONTRACTION_MAX_START:
                raise RecordValidationError("contraction start must be within 24 hours")
            if not 1 <= duration <= cls.CONTRACTION_MAX_DURATION:
                raise RecordValidationError("contraction duration must be 1-600 seconds")
            # 上一次结束之后才能开始下一次；这同时保证了开始时刻不递减。
            if start < previous_end:
                raise RecordValidationError("contractions must not overlap")
            previous_end = start + duration

    # 「我们出发去医院了」：原因决定家人看到的那句话，备注一句就够。
    HOSPITAL_TRIP_REASONS: ClassVar[frozenset[str]] = frozenset(
        {"contractions", "water_broke", "bleeding", "fetal_movement", "scheduled", "other"}
    )
    HOSPITAL_TRIP_NOTE_LIMIT: ClassVar[int] = 200

    @classmethod
    def _validate_hospital_trip(cls, data: dict[str, Any], content: str | None) -> None:
        if set(data) - {"reason", "contraction_record_id"}:
            raise RecordValidationError(
                "hospital trip records only accept reason and contraction_record_id"
            )
        reason = data.get("reason")
        if not isinstance(reason, str) or reason not in cls.HOSPITAL_TRIP_REASONS:
            raise RecordValidationError("hospital trip reason is not supported")
        linked = data.get("contraction_record_id")
        if linked is not None and not _is_uuid_text(linked):
            raise RecordValidationError("hospital trip contraction_record_id must be a UUID string")
        if content is not None and len(content) > cls.HOSPITAL_TRIP_NOTE_LIMIT:
            raise RecordValidationError("hospital trip note must be at most 200 characters")

    @staticmethod
    def assert_visibility_allowed(record_type: RecordType, visibility: RecordVisibility) -> None:
        """去医院这条的意义就是让家人看到，不能设为仅自己可见。"""
        if record_type is RecordType.hospital_trip and visibility is RecordVisibility.private:
            raise RecordValidationError("hospital trip records must be visible to the family")

    @classmethod
    def _validate_knowledge(cls, data: dict[str, Any], title: str | None) -> None:
        if not isinstance(title, str) or not title.strip():
            raise RecordValidationError("knowledge entries require a title")

        category = data.get("category")
        if category not in cls.KNOWLEDGE_CATEGORIES:
            # 分类决定条目出现在哪张卡下。写错等于存进了一个看不见的地方。
            raise RecordValidationError(f"unsupported knowledge category: {category}")

        form = data.get("form")
        if form == "recipe":
            cls._require_nonempty_strings(data, "ingredients")
            cls._require_nonempty_strings(data, "steps")
            # 用途是找菜谱的入口——孕期找菜的起点几乎总是「我缺铁，吃什么」。
            # 可选：不是每道菜都有明确用途。
            if "purposes" in data:
                cls._require_nonempty_strings(data, "purposes")
        elif form == "food_rule":
            # 结论可选。「补铁要配维C」「孕吐时少食多餐」归不进任何一档，
            # 强制结论只会逼出牵强的判断。
            verdict = data.get("verdict")
            if verdict is not None and verdict not in cls.FOOD_VERDICTS:
                raise RecordValidationError(
                    "food_rule verdict must be one of safe / limit / avoid"
                )
            # 原因仍然必填：只给结论不给原因，用户没法判断这条是否适用于自己。
            cls._require_text(data, "reason")
        elif form == "howto":
            cls._require_nonempty_strings(data, "steps")
        elif form == "tip":
            cls._require_text(data, "body")
        else:
            raise RecordValidationError(f"unsupported knowledge form: {form}")

    @staticmethod
    def _require_nonempty_strings(data: dict[str, Any], field: str) -> None:
        values = data.get(field)
        if (
            not isinstance(values, list)
            or not values
            or not all(isinstance(v, str) and v.strip() for v in values)
        ):
            raise RecordValidationError(f"knowledge {field} must be a non-empty string list")

    @staticmethod
    def _require_text(data: dict[str, Any], field: str) -> None:
        value = data.get(field)
        if not isinstance(value, str) or not value.strip():
            raise RecordValidationError(f"knowledge {field} must be non-empty text")

    @classmethod
    def _validate_checkup_metrics(cls, metrics: Any) -> None:
        if metrics is None:
            return
        if not isinstance(metrics, dict):
            raise RecordValidationError("checkup metrics must be a JSON object")
        for key, value in metrics.items():
            bounds = cls.CHECKUP_METRIC_RANGES.get(key)
            if bounds is None:
                # 未知指标名要挡住——否则错别字会静默变成一条永远没人看的数据。
                raise RecordValidationError(f"unsupported checkup metric: {key}")
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise RecordValidationError(f"checkup metric {key} must be a number")
            low, high = bounds
            if not low <= float(value) <= high:
                raise RecordValidationError(
                    f"checkup metric {key} is outside the plausible range {low}-{high}"
                )
        systolic = metrics.get("systolic")
        diastolic = metrics.get("diastolic")
        if (
            isinstance(systolic, (int, float))
            and isinstance(diastolic, (int, float))
            and float(diastolic) >= float(systolic)
        ):
            raise RecordValidationError("diastolic pressure must be below systolic")

    @classmethod
    def _validate_other_items(cls, items: Any) -> None:
        if items is None:
            return
        if not isinstance(items, list):
            raise RecordValidationError("checkup other_items must be a list")
        if len(items) > cls.MAX_OTHER_ITEMS:
            raise RecordValidationError(
                f"checkup other_items allows at most {cls.MAX_OTHER_ITEMS} entries"
            )
        allowed_keys = {"name", "value", "unit", "reference", "flag"}
        for entry in items:
            if not isinstance(entry, dict):
                raise RecordValidationError("checkup other_items entries must be JSON objects")
            unknown = set(entry) - allowed_keys
            if unknown:
                # 和指标一样挡住未知键，错别字不能静默变成没人读的数据。
                raise RecordValidationError(
                    f"unsupported checkup other_items field: {sorted(unknown)[0]}"
                )
            for field in ("name", "value"):
                value = entry.get(field)
                if not isinstance(value, str) or not value.strip() or len(value) > 40:
                    raise RecordValidationError(
                        f"checkup other_items {field} must be non-empty text"
                        " of at most 40 characters"
                    )
            for field, limit in (("unit", 20), ("reference", 60)):
                value = entry.get(field)
                if value is not None and (not isinstance(value, str) or len(value) > limit):
                    raise RecordValidationError(
                        f"checkup other_items {field} must be text of at most {limit} characters"
                    )
            flag = entry.get("flag")
            # 先判类型：列表等不可哈希的值直接 in frozenset 会抛 TypeError。
            if flag is not None and (
                not isinstance(flag, str) or flag not in cls.OTHER_ITEM_FLAGS
            ):
                raise RecordValidationError(
                    "checkup other_items flag must be high, low or abnormal"
                )

    @staticmethod
    def _with_defaults(record_type: RecordType, structured_data: dict[str, Any], *, occurred_at: datetime | None = None) -> dict[str, Any]:
        """把可选状态字段的默认值显式写进去。

        消费方（列表、统计、客户端）读到的永远是完整结构，
        不必各自记住「没有 answered 就等于未回答」。
        """
        if record_type.value in CARE_TYPES:
            return normalize_care(record_type.value, structured_data, occurred_at)
        if record_type is RecordType.question:
            return {"answered": False, **structured_data}
        if record_type is RecordType.checklist:
            return {"done": False, **structured_data}
        if record_type is RecordType.memory:
            return {"kind": structured_data["kind"], "text": structured_data["text"].strip()}
        if record_type is RecordType.contraction:
            contractions = structured_data["contractions"]
            return {"contractions": contractions, "summary": contraction_summary(contractions)}
        if record_type is RecordType.mood:
            return {"mood": structured_data["mood"], "tags": list(structured_data.get("tags", []))}
        if record_type is RecordType.epds:
            answers = list(structured_data["answers"])
            return {"version": structured_data["version"], "answers": answers,
                    "period": structured_data.get("period", "manual"), **epds_result(answers)}
        return structured_data

    @classmethod
    def _validate_payload(
        cls,
        record_type: RecordType,
        structured_data: dict[str, Any],
        content: str | None,
        title: str | None = None,
        *, occurred_at: datetime | None = None,
    ) -> None:
        if record_type.value in CARE_TYPES:
            if occurred_at is None:
                raise RecordValidationError("照护记录需要实际发生时间")
            validate_care(record_type.value, structured_data, occurred_at)
            return
        if record_type is RecordType.mood:
            validate_mood(structured_data, content)
            return
        if record_type is RecordType.epds:
            validate_epds(structured_data)
            return
        if record_type is RecordType.memory:
            if set(structured_data) != {"kind", "text"}:
                raise RecordValidationError("记忆只能包含类别和一句话")
            if structured_data["kind"] not in (
                "allergy", "history", "medication", "care", "preference", "other"
            ):
                raise RecordValidationError("记忆类别不支持")
            text = structured_data["text"]
            if not isinstance(text, str) or not 1 <= len(text.strip()) <= 80:
                raise RecordValidationError("记忆请写成 1–80 个字的一句话")
            return
        if record_type is RecordType.symptom:
            symptoms = structured_data.get("symptoms")
            severity = structured_data.get("severity")
            if (
                not isinstance(symptoms, list)
                or not symptoms
                or not all(isinstance(symptom, str) and symptom.strip() for symptom in symptoms)
            ):
                raise RecordValidationError("symptom records require a non-empty symptoms string list")
            if isinstance(severity, bool) or not isinstance(severity, int) or not 1 <= severity <= 5:
                raise RecordValidationError("symptom severity must be an integer from 1 through 5")
            note = structured_data.get("note")
            if note is not None and not isinstance(note, str):
                raise RecordValidationError("symptom note must be a string when provided")
            return

        if record_type is RecordType.checkup:
            for field in ("hospital", "exam_items", "result", "doctor_advice"):
                value = structured_data.get(field)
                if value is not None and not isinstance(value, str):
                    raise RecordValidationError(f"checkup {field} must be a string")
            cls._validate_checkup_metrics(structured_data.get("metrics"))
            cls._validate_other_items(structured_data.get("other_items"))
            return

        if record_type is RecordType.note:
            if not isinstance(content, str) or not content.strip():
                raise RecordValidationError("note records require non-empty content")
            return

        # 「想问医生」：问题本身就是一句话，答案与已答状态放结构化字段。
        if record_type is RecordType.question:
            if not isinstance(content, str) or not content.strip():
                raise RecordValidationError("question records require non-empty content")
            answered = structured_data.get("answered", False)
            if not isinstance(answered, bool):
                raise RecordValidationError("question answered must be a boolean")
            answer = structured_data.get("answer")
            if answer is not None and not isinstance(answer, str):
                raise RecordValidationError("question answer must be a string when provided")
            # 从产检报告里攒出来的问题指回那份报告；手动加的问题没有这个字段。
            report_id = structured_data.get("report_id")
            if report_id is not None and not _is_uuid_text(report_id):
                raise RecordValidationError("question report_id must be a UUID string")
            return

        # 知识条目：由对话积累的资料。分类决定它出现在哪张卡下，
        # 形态决定它怎么渲染。
        if record_type is RecordType.knowledge:
            cls._validate_knowledge(structured_data, title)
            return

        # 「办事指南」「待产准备」共用：内容库给条目，这里只存勾选状态。
        if record_type is RecordType.checklist:
            for field in ("collection", "item_id"):
                value = structured_data.get(field)
                if not isinstance(value, str) or not value.strip():
                    raise RecordValidationError(f"checklist {field} must be a non-empty string")
            done = structured_data.get("done", False)
            if not isinstance(done, bool):
                raise RecordValidationError("checklist done must be a boolean")
            return

        if record_type is RecordType.fetal_movement:
            cls._validate_fetal_movement(structured_data)
            return

        if record_type is RecordType.contraction:
            cls._validate_contraction(structured_data)
            return

        if record_type is RecordType.hospital_trip:
            cls._validate_hospital_trip(structured_data, content)
            return

        raise RecordValidationError(f"unsupported record type: {record_type}")


def _validate_attachment_refs(refs: list[str]) -> None:
    """附件引用只能是本系统的附件编号，不能是外部地址或文件路径。

    归属（同家庭、未挂到别处）由新建记录的用例查附件表核对，这里只管形状。
    """
    if len(refs) > MAX_ATTACHMENTS_PER_RECORD:
        raise RecordValidationError("一条记录最多挂 4 张图片")
    for ref in refs:
        try:
            UUID(ref)
        except (TypeError, ValueError) as error:
            raise RecordValidationError("附件引用必须是附件编号") from error


def _is_uuid_text(value: Any) -> bool:
    """是否为标准写法的 UUID 字符串。要求标准写法，客户端才能直接按字符串相等去配对记录。"""
    if not isinstance(value, str):
        return False
    try:
        return str(UUID(value)) == value
    except ValueError:
        return False
