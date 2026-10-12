# 分娩模式 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 孕晚期家庭能在 App 里给宫缩计时，按 5-1-1 知道什么时候该出发；在一页里找到立即就医的情况、待产包和 120；出发时一键「我们出发去医院了」，家人打开 App 就能看到。

**Architecture:**
- 后端新增两种记录类型 `contraction`、`hospital_trip`，复用 records 表和接口。`contraction` 的摘要由服务端从原始数据算出。
- iOS 分三层：
  - 纯数据：计时器、档位计算、横幅筛选。不碰计时器，所有判断按时间戳和传入的「现在」计算。
  - `ContractionStore`：本地断点、保存、重试、历史。照抄 `FetalMovementStore` 的作用域与队列做法。
  - 界面：计时页、分娩页、去医院确认页、首页置顶卡与分娩准备卡、各入口。

**Tech Stack:** FastAPI + pytest；Eve agent（TypeScript + zod + node:test）；SwiftUI（iOS 17+，`@Observable`）+ XCTest / XCUITest。

规格：`docs/superpowers/specs/2026-10-12-labor-mode-design.md`（以下简称「规格」）。

## Global Constraints

- 所有面向用户的文字、注释、提交信息用简体中文。
- 记录类型：`contraction`（宫缩计时）、`hospital_trip`（去医院）。不新增接口，不需要数据库迁移。
- `contraction.structured_data.contractions`：
  - 1–500 项，每项 `{"start": int, "duration": int}`。
  - `start` 为 0–86400 的整数，首项必须为 0，不递减。
  - `duration` 为 1–600 的整数。
  - 不重叠：`start[i] >= start[i-1] + duration[i-1]`。
- `contraction.structured_data.summary` 由服务端计算并覆盖客户端传入的值，字段为 `count`、`last_hour_count`、`avg_interval_seconds`（可为 null）、`avg_duration_seconds`、`pattern ∈ {early, approaching, go}`。
- 档位规则（T = 最后一次宫缩的开始时刻）：
  - `go`：开始时刻在 `[T−3600, T]` 内的宫缩，平均间隔 ≤ 300 秒，平均持续 ≥ 50 秒，且 `T − 窗口内第一次开始 ≥ 3300`。
  - `approaching`：开始时刻在 `[T−1800, T]` 内的宫缩 ≥ 4 次，且平均间隔 ≤ 420 秒。
  - 其他为 `early`。
  - 平均间隔 =（窗口内最后一次开始 − 第一次开始）÷（次数 − 1），次数 < 2 时为 null。
  - 阈值用精确值比较，存档值四舍五入到整秒（Python 用 `math.floor(x + 0.5)`，Swift 用 `.rounded()`）。
- iOS 实时档位，按 T = 现在：
  - 停顿回落：距最后一次宫缩结束 > 1200 秒且没在宫缩中 → 显示 `early`，并提示「已经 N 分钟没有宫缩了」。
  - 早产警示 `pretermAlert`：孕周 < 37，且最近 1200 秒内开始的宫缩 ≥ 4 次，或最近 3600 秒内 ≥ 8 次。
- 单次宫缩超过 180 秒未结束：提示「持续剧痛不缓解请立即去医院」。被系统杀掉后回来超过 600 秒的，截断为 600 秒。
- 最后一次宫缩结束超过 6 小时（21600 秒）的未保存计时：先让用户选「保存」或「丢弃」，才能开始新的计时。
- `hospital_trip`：
  - `structured_data` 为 `{"reason": ..., "contraction_record_id"?: 小写标准 UUID 字符串}`。
  - `reason ∈ {contractions, water_broke, bleeding, fetal_movement, scheduled, other}`。
  - `content` 是可选备注，≤ 200 字。
  - 必须家庭可见：新建为 `private` 或改成 `private` 都返回 409。
  - `title` 固定「我们出发去医院了」。
- 首页去医院横幅：24 小时内、未删除、最新的一条 `hospital_trip`。作者看到「说错了，撤回」，其他人看到「知道了」（本机按记录 id 隐藏）。
- 首页「分娩准备」卡：孕 36 周起显示。分娩页和计时页：孕周 < 37 时顶部常驻早产提示。
- 医学文案集中在 `Features/Labor/LaborCopy.swift` 常量里，便于复核。不说「正常」，也不说「还不用去」。
- iOS 新文件手工登记 `apps/ios/AimApp.xcodeproj/project.pbxproj` 四处：PBXBuildFile、PBXFileReference、所在 group 的 children、对应 target 的 Sources 构建阶段。
  - 编号从 `…180` 起，用前先 `grep -c 'A10000000000000000000180' apps/ios/AimApp.xcodeproj/project.pbxproj` 确认未被占用（应为 0）。
  - 格式照抄 `Features/FetalMovement/FetalMovementStore.swift`（App，编号 161）与 `Tests/FetalMovementModelsTests.swift`（测试，编号 164）的四处登记。
  - App 文件的 `path` 照 161 的写法，相对所在 group；测试文件的 `path` 照 164 的写法。
- 项目里有自家的 `TimelineView` 类型；需要 SwiftUI 的定时刷新时必须写 `SwiftUI.TimelineView`。
- 模拟器用 iPhone 18 Pro；UI 测试连本地 `make dev` 栈。已知两条既有 UI 用例失败（`testGlobalAgentButtonShowsCurrentTabContext`、`testAPastConversationCanBeReopenedFromHistory`），与本计划无关。
- 跑 iOS 单元测试：`cd apps/ios && xcodebuild test -project AimApp.xcodeproj -scheme AimApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:AimAppTests/<类名>`。若 `-only-testing` 的 target 名不对，先 `xcodebuild -list -project AimApp.xcodeproj` 查。

## 文件结构

共享：
- Create `contracts/fixtures/contraction-summary-vectors.json` —— 档位计算的测试向量。API 测试直接读取；iOS 测试内嵌同一份拷贝。

API（`services/api/`）：
- Modify `src/aim_api/contexts/records/domain/record.py` —— 两种新类型的校验与摘要。
- Create `src/aim_api/contexts/records/domain/contraction.py` —— 纯函数 `contraction_summary()`。
- Modify `src/aim_api/contexts/records/application/commands/update_record.py` —— 去医院记录不能改成私密，宫缩记录更新后重算摘要。
- Modify `src/aim_api/composition/family/activity.py` —— 类型显示名。
- Create `tests/domain/records/test_contraction.py`、`tests/domain/records/test_hospital_trip.py`；Modify `tests/integration/records/test_records_api.py`。
- 重新生成 `contracts/public-api/openapi.json`、`contracts/agent-tools/openapi.json`（`make contracts`）。

Agent（`services/agent/`）：
- Modify `agent/tools/list_records.ts`、`agent/instructions.md`、`tests/tools/records.test.ts`。

内容：
- Modify `content/encyclopedia/birth.yaml`（`birth.when-to-go`「规律宫缩时」）、`content/README.md`。

iOS（`apps/ios/AimApp/`）：
- Modify `Features/Records/RecordModels.swift`、`Generated/OpenAPI/Models.swift`、`Clients/BusinessAPIClient/BusinessRepository.swift`、`Features/Records/RecordsView.swift`、`Features/Records/RecordDetailView.swift`、`Features/Records/RecordComposerView.swift` —— 新记录类型贯通。
- Create `Features/Labor/ContractionModels.swift`（180）—— 计时器、档位、格式化、会话。纯数据。
- Create `Features/Labor/ContractionStore.swift`（181）—— 断点、保存、重试、历史、陈旧断点。
- Create `Features/Labor/LaborCopy.swift`（182）—— 医学文案常量。
- Create `Features/Labor/ContractionTimerView.swift`（183）—— 计时页。
- Create `Features/Labor/LaborView.swift`（184）—— 分娩页、「我们出发去医院了」确认页。
- Create `Features/Labor/HospitalTrip.swift`（185）—— 去医院记录的草稿、横幅筛选、本机已读。
- Create `Features/Labor/LaborHomeCards.swift`（186）—— 首页置顶卡（横幅 / 计时中）与分娩准备卡。
- Create `Tests/ContractionModelsTests.swift`（187）、`Tests/ContractionStoreTests.swift`（188）、`Tests/HospitalTripTests.swift`（189）。
- Modify `App/AimApp.swift`、`Features/Home/HomeDashboardView.swift`、`Features/Home/HomeDashboardStore.swift`、`Features/Library/LibraryCategoryDetail.swift`、`Features/Library/EncyclopediaEntryView.swift`、`UITests/CoreJourneyUITests.swift`。

---

### Task 1: 后端 `contraction` 记录与摘要计算

**Files:**
- Create: `contracts/fixtures/contraction-summary-vectors.json`
- Create: `services/api/src/aim_api/contexts/records/domain/contraction.py`
- Modify: `services/api/src/aim_api/contexts/records/domain/record.py`（`RecordType` :13-21；`_with_defaults` :317；`_validate_payload` 末尾 :413 前）
- Modify: `services/api/src/aim_api/contexts/records/application/commands/update_record.py:56-61`
- Test: `services/api/tests/domain/records/test_contraction.py`

**Interfaces:**
- Produces：
  - `RecordType.contraction = "contraction"`。
  - `aim_api.contexts.records.domain.contraction.contraction_summary(contractions: list[dict]) -> dict`，返回 `{"count", "last_hour_count", "avg_interval_seconds", "avg_duration_seconds", "pattern"}`。
  - 测试向量文件的格式：`{"vectors": [{"name": str, "contractions": [[start, duration], ...], "expected": {summary 字段}}]}`。Task 5 的 iOS 测试内嵌同一份内容。

- [ ] **Step 1: 写测试向量**

`contracts/fixtures/contraction-summary-vectors.json`。每组 `contractions` 写成 `[start, duration]` 二元组，便于两边测试读：

```json
{
  "_comment": "宫缩档位计算的共享测试向量。API（tests/domain/records/test_contraction.py）直接读取；iOS（Tests/ContractionModelsTests.swift）内嵌同一份拷贝，改这里要同步改那边。",
  "vectors": [
    {
      "name": "只有一次",
      "contractions": [[0, 60]],
      "expected": {"count": 1, "last_hour_count": 1, "avg_interval_seconds": null, "avg_duration_seconds": 60, "pattern": "early"}
    },
    {
      "name": "十分钟一次，还早",
      "contractions": [[0, 40], [600, 40], [1200, 40], [1800, 40]],
      "expected": {"count": 4, "last_hour_count": 4, "avg_interval_seconds": 600, "avg_duration_seconds": 40, "pattern": "early"}
    },
    {
      "name": "最近半小时 4 次、7 分钟一次，接近",
      "contractions": [[0, 45], [420, 45], [840, 45], [1260, 45]],
      "expected": {"count": 4, "last_hour_count": 4, "avg_interval_seconds": 420, "avg_duration_seconds": 45, "pattern": "approaching"}
    },
    {
      "name": "最近半小时 4 次、但 7 分 1 秒一次，差一点",
      "contractions": [[0, 45], [421, 45], [842, 45], [1263, 45]],
      "expected": {"count": 4, "last_hour_count": 4, "avg_interval_seconds": 421, "avg_duration_seconds": 45, "pattern": "early"}
    },
    {
      "name": "满一小时、5 分钟一次、每次 50 秒：符合 5-1-1",
      "contractions": [[0, 50], [300, 50], [600, 50], [900, 50], [1200, 50], [1500, 50], [1800, 50], [2100, 50], [2400, 50], [2700, 50], [3000, 50], [3300, 50]],
      "expected": {"count": 12, "last_hour_count": 12, "avg_interval_seconds": 300, "avg_duration_seconds": 50, "pattern": "go"}
    },
    {
      "name": "跨度只有 54 分 59 秒：还不算满一小时",
      "contractions": [[0, 50], [299, 50], [599, 50], [899, 50], [1199, 50], [1499, 50], [1799, 50], [2099, 50], [2399, 50], [2699, 50], [2999, 50], [3299, 50]],
      "expected": {"count": 12, "last_hour_count": 12, "avg_interval_seconds": 300, "avg_duration_seconds": 50, "pattern": "approaching"}
    },
    {
      "name": "满一小时但平均持续 49 秒",
      "contractions": [[0, 49], [300, 49], [600, 49], [900, 49], [1200, 49], [1500, 49], [1800, 49], [2100, 49], [2400, 49], [2700, 49], [3000, 49], [3300, 49]],
      "expected": {"count": 12, "last_hour_count": 12, "avg_interval_seconds": 300, "avg_duration_seconds": 49, "pattern": "approaching"}
    },
    {
      "name": "满一小时但 5 分 30 秒一次",
      "contractions": [[0, 60], [330, 60], [660, 60], [990, 60], [1320, 60], [1650, 60], [1980, 60], [2310, 60], [2640, 60], [2970, 60], [3300, 60]],
      "expected": {"count": 11, "last_hour_count": 11, "avg_interval_seconds": 330, "avg_duration_seconds": 60, "pattern": "approaching"}
    },
    {
      "name": "一小时以前的宫缩不进窗口",
      "contractions": [[0, 30], [1000, 30], [5000, 60], [5300, 60], [5600, 60], [5900, 60]],
      "expected": {"count": 6, "last_hour_count": 4, "avg_interval_seconds": 300, "avg_duration_seconds": 60, "pattern": "approaching"}
    },
    {
      "name": "平均值四舍五入",
      "contractions": [[0, 50], [301, 51], [602, 50]],
      "expected": {"count": 3, "last_hour_count": 3, "avg_interval_seconds": 301, "avg_duration_seconds": 50, "pattern": "early"}
    }
  ]
}
```

算一下关键几组：
- 「跨度只有 54 分 59 秒」：跨度 3299 < 3300，不判 `go`；平均间隔 3299/11 = 299.9，四舍五入为 300；半小时窗口 `[1499, 3299]` 内 7 次，平均间隔 300 ≤ 420，判 `approaching`。
- 「平均值四舍五入」：平均间隔 301，平均持续 151/3 = 50.33，四舍五入为 50。

- [ ] **Step 2: 写领域测试（先失败）**

`services/api/tests/domain/records/test_contraction.py`：

```python
from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import pytest

from aim_api.contexts.records.domain.contraction import contraction_summary
from aim_api.contexts.records.domain.errors import RecordValidationError
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility

NOW = datetime(2026, 10, 12, 3, 0, tzinfo=UTC)
VECTORS = json.loads(
    (Path(__file__).resolve().parents[5] / "contracts/fixtures/contraction-summary-vectors.json").read_text(
        encoding="utf-8"
    )
)["vectors"]


def entries(pairs: list[list[int]]) -> list[dict]:
    return [{"start": start, "duration": duration} for start, duration in pairs]


def make(structured_data: dict) -> Record:
    return Record.create(
        record_id=uuid4(),
        pregnancy_id=uuid4(),
        family_id=uuid4(),
        author_account_id=uuid4(),
        record_type=RecordType.contraction,
        occurred_at=NOW,
        visibility=RecordVisibility.family,
        title="宫缩计时 · 3 次",
        content=None,
        structured_data=structured_data,
        now=NOW,
    )


@pytest.mark.parametrize("vector", VECTORS, ids=[v["name"] for v in VECTORS])
def test_summary_matches_shared_vectors(vector):
    assert contraction_summary(entries(vector["contractions"])) == vector["expected"]


class TestContractionRecord:
    def test_server_computes_and_overrides_the_summary(self):
        record = make({
            "contractions": entries([[0, 60], [300, 60]]),
            "summary": {"pattern": "go", "count": 99},
        })
        assert record.structured_data["summary"] == {
            "count": 2,
            "last_hour_count": 2,
            "avg_interval_seconds": 300,
            "avg_duration_seconds": 60,
            "pattern": "early",
        }

    @pytest.mark.parametrize(
        "contractions",
        [
            [],
            entries([[5, 60]]),  # 首项必须为 0
            entries([[0, 60], [30, 60]]),  # 重叠
            entries([[0, 60], [300, 60], [200, 60]]),  # 递减
            entries([[0, 0]]),  # 持续不足 1 秒
            entries([[0, 601]]),  # 持续超过 10 分钟
            entries([[0, 60], [86401, 60]]),  # 超过 24 小时
            [{"start": 0}],  # 缺 duration
            [{"start": 0, "duration": True}],  # 布尔不算整数
            [[0, 60]],  # 必须是对象
        ],
    )
    def test_invalid_contractions_are_rejected(self, contractions):
        with pytest.raises(RecordValidationError):
            make({"contractions": contractions})

    def test_at_most_500_contractions(self):
        many = entries([[i * 120, 60] for i in range(501)])
        with pytest.raises(RecordValidationError):
            make({"contractions": many})
        make({"contractions": many[:500]})

    def test_back_to_back_contractions_are_allowed(self):
        make({"contractions": entries([[0, 60], [60, 60]])})

    def test_unknown_fields_are_rejected(self):
        with pytest.raises(RecordValidationError):
            make({"contractions": entries([[0, 60]]), "extra": 1})
```

注意 `parents[5]`：本文件在 `services/api/tests/domain/records/`，`parents[0]` 是 `records`，`parents[1]` 是 `domain`，`parents[2]` 是 `tests`，`parents[3]` 是 `api`，`parents[4]` 是 `services`，`parents[5]` 是仓库根。写完先 `python3 -c` 打印一次路径确认。

- [ ] **Step 3: 运行，确认失败**

Run: `cd services/api && python3 -m pytest tests/domain/records/test_contraction.py -q`
Expected: FAIL，`ModuleNotFoundError: aim_api.contexts.records.domain.contraction`

- [ ] **Step 4: 实现摘要计算**

`services/api/src/aim_api/contexts/records/domain/contraction.py`：

```python
"""宫缩计时的摘要：最近一小时的次数、平均间隔、平均持续与 5-1-1 档位。

以最后一次宫缩的开始时刻为参考，数据定了结论就定了；iOS 计时页用同一套规则
（Features/Labor/ContractionModels.swift 的 ContractionMath），两边共用
contracts/fixtures/contraction-summary-vectors.json 的测试向量。
"""

from __future__ import annotations

import math
from typing import Any

HOUR_SECONDS = 3600
HALF_HOUR_SECONDS = 1800
# 「持续 1 小时」：第一次与最后一次开始之间最多差一个间隔，所以放宽到 55 分钟。
GO_MIN_SPAN_SECONDS = 3300
GO_MAX_INTERVAL_SECONDS = 300
# 手按「结束」普遍偏早，「每次约 1 分钟」按平均 50 秒判断。
GO_MIN_DURATION_SECONDS = 50
APPROACHING_MIN_COUNT = 4
APPROACHING_MAX_INTERVAL_SECONDS = 420


def _round(value: float) -> int:
    # 四舍五入到整秒；不用 round()，它是银行家舍入，和 iOS 的 .rounded() 不一致。
    return math.floor(value + 0.5)


def _average_interval(starts: list[int]) -> float | None:
    if len(starts) < 2:
        return None
    return (starts[-1] - starts[0]) / (len(starts) - 1)


def contraction_summary(contractions: list[dict[str, Any]]) -> dict[str, Any]:
    starts = [item["start"] for item in contractions]
    durations = [item["duration"] for item in contractions]
    latest = starts[-1]

    hour = [i for i, start in enumerate(starts) if start >= latest - HOUR_SECONDS]
    half = [i for i, start in enumerate(starts) if start >= latest - HALF_HOUR_SECONDS]
    hour_starts = [starts[i] for i in hour]
    hour_interval = _average_interval(hour_starts)
    hour_duration = sum(durations[i] for i in hour) / len(hour)
    half_interval = _average_interval([starts[i] for i in half])

    pattern = "early"
    if (
        hour_interval is not None
        and hour_interval <= GO_MAX_INTERVAL_SECONDS
        and hour_duration >= GO_MIN_DURATION_SECONDS
        and latest - hour_starts[0] >= GO_MIN_SPAN_SECONDS
    ):
        pattern = "go"
    elif (
        len(half) >= APPROACHING_MIN_COUNT
        and half_interval is not None
        and half_interval <= APPROACHING_MAX_INTERVAL_SECONDS
    ):
        pattern = "approaching"

    return {
        "count": len(contractions),
        "last_hour_count": len(hour),
        "avg_interval_seconds": None if hour_interval is None else _round(hour_interval),
        "avg_duration_seconds": _round(hour_duration),
        "pattern": pattern,
    }
```

- [ ] **Step 5: 接进记录模型**

`record.py`：

1. `RecordType` 加一行 `contraction = "contraction"`，放在 `memory` 后面。
2. 文件顶部 import：`from aim_api.contexts.records.domain.contraction import contraction_summary`。
3. 在 `_validate_knowledge` 之前加常量和校验：

```python
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
```

4. `_validate_payload` 里，在 `if record_type is RecordType.fetal_movement:` 分支后加：

```python
        if record_type is RecordType.contraction:
            cls._validate_contraction(structured_data)
            return
```

5. `_with_defaults` 里加（在 `return structured_data` 前）：

```python
        if record_type is RecordType.contraction:
            contractions = structured_data["contractions"]
            return {"contractions": contractions, "summary": contraction_summary(contractions)}
```

6. `update_record.py` 第 59-61 行：把只对 memory 调 `_with_defaults` 的地方改为对所有类型都调，memory 的标题照旧单独处理：

```python
    record.structured_data = Record._with_defaults(record.record_type, record.structured_data)
    if record.record_type is RecordType.memory:
        record.title = record.structured_data["text"][:40]
```

改前确认：`_with_defaults` 对 question、checklist 是「补缺省值、已有值优先」，对其他类型原样返回，所以对所有类型都调不改变现有行为。跑 Step 6 的全量测试来验证。

- [ ] **Step 6: 运行测试**

Run: `cd services/api && python3 -m pytest tests/domain/records -q && python3 -m pytest -q`
Expected: 全部 PASS（全量测试需要本地 PostgreSQL，`make dev` 起着即可）。

- [ ] **Step 7: 提交**

```bash
git add contracts/fixtures/contraction-summary-vectors.json services/api/src/aim_api/contexts/records services/api/tests/domain/records/test_contraction.py
git commit -m "feat(api): 宫缩计时记录与服务端 5-1-1 摘要"
```

---

### Task 2: 后端 `hospital_trip` 记录、家庭动态与契约

**Files:**
- Modify: `services/api/src/aim_api/contexts/records/domain/record.py`
- Modify: `services/api/src/aim_api/contexts/records/application/commands/update_record.py`
- Modify: `services/api/src/aim_api/composition/family/activity.py:23-31`
- Test: `services/api/tests/domain/records/test_hospital_trip.py`、`services/api/tests/integration/records/test_records_api.py`
- Regenerate: `contracts/public-api/openapi.json`、`contracts/agent-tools/openapi.json`

**Interfaces:**
- Consumes：Task 1 的 `RecordType.contraction`。
- Produces：
  - `RecordType.hospital_trip = "hospital_trip"`。
  - `Record.HOSPITAL_TRIP_REASONS`。
  - 新建或更新为 `private` 时抛 `RecordValidationError`（HTTP 409）。

- [ ] **Step 1: 写领域测试（先失败）**

`services/api/tests/domain/records/test_hospital_trip.py`：

```python
from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from aim_api.contexts.records.domain.errors import RecordValidationError
from aim_api.contexts.records.domain.record import Record, RecordType, RecordVisibility

NOW = datetime(2026, 10, 12, 3, 0, tzinfo=UTC)


def make(structured_data: dict, *, content: str | None = None,
         visibility: RecordVisibility = RecordVisibility.family) -> Record:
    return Record.create(
        record_id=uuid4(),
        pregnancy_id=uuid4(),
        family_id=uuid4(),
        author_account_id=uuid4(),
        record_type=RecordType.hospital_trip,
        occurred_at=NOW,
        visibility=visibility,
        title="我们出发去医院了",
        content=content,
        structured_data=structured_data,
        now=NOW,
    )


class TestHospitalTrip:
    @pytest.mark.parametrize(
        "reason", ["contractions", "water_broke", "bleeding", "fetal_movement", "scheduled", "other"]
    )
    def test_every_reason_is_accepted(self, reason):
        assert make({"reason": reason}).structured_data == {"reason": reason}

    def test_unknown_reason_is_rejected(self):
        with pytest.raises(RecordValidationError):
            make({"reason": "bored"})

    def test_reason_is_required(self):
        with pytest.raises(RecordValidationError):
            make({})

    def test_a_linked_contraction_must_be_a_lowercase_uuid(self):
        linked = str(uuid4())
        make({"reason": "contractions", "contraction_record_id": linked})
        with pytest.raises(RecordValidationError):
            make({"reason": "contractions", "contraction_record_id": linked.upper()})
        with pytest.raises(RecordValidationError):
            make({"reason": "contractions", "contraction_record_id": "abc"})

    def test_note_is_at_most_200_characters(self):
        make({"reason": "other"}, content="字" * 200)
        with pytest.raises(RecordValidationError):
            make({"reason": "other"}, content="字" * 201)

    def test_it_cannot_be_private(self):
        with pytest.raises(RecordValidationError):
            make({"reason": "contractions"}, visibility=RecordVisibility.private)

    def test_unknown_fields_are_rejected(self):
        with pytest.raises(RecordValidationError):
            make({"reason": "other", "eta": "10 分钟"})
```

- [ ] **Step 2: 运行，确认失败**

Run: `cd services/api && python3 -m pytest tests/domain/records/test_hospital_trip.py -q`
Expected: FAIL，`AttributeError: hospital_trip`

- [ ] **Step 3: 实现**

`record.py`：

1. `RecordType` 加 `hospital_trip = "hospital_trip"`。
2. 常量和校验，放在 `_validate_contraction` 后面：

```python
    # 「我们出发去医院了」：原因决定家人看到的那句话，备注一句就够。
    HOSPITAL_TRIP_REASONS: ClassVar[frozenset[str]] = frozenset(
        {"contractions", "water_broke", "bleeding", "fetal_movement", "scheduled", "other"}
    )
    HOSPITAL_TRIP_NOTE_LIMIT: ClassVar[int] = 200

    @classmethod
    def _validate_hospital_trip(cls, data: dict[str, Any], content: str | None) -> None:
        if set(data) - {"reason", "contraction_record_id"}:
            raise RecordValidationError("hospital trip records only accept reason and contraction_record_id")
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
```

3. `_validate_payload` 加分支（在 contraction 分支后）：

```python
        if record_type is RecordType.hospital_trip:
            cls._validate_hospital_trip(structured_data, content)
            return
```

4. `create()` 里 `cls._validate_payload(...)` 之前加 `cls.assert_visibility_allowed(record_type, visibility)`。

`update_record.py`：在 `if "visibility" in command.changes: record.visibility = ...` 这一句之后加：

```python
    Record.assert_visibility_allowed(record.record_type, record.visibility)
```

`activity.py` 的 `_RECORD_TYPE_NAMES` 加两行：

```python
    "contraction": "宫缩",
    "hospital_trip": "去医院",
```

- [ ] **Step 4: 写集成测试**

在 `tests/integration/records/test_records_api.py` 末尾加。沿用文件里已有的 `_phone`、`_headers`、`_create_pregnancy`、`_create_record` 辅助函数：

```python
def test_contraction_and_hospital_trip_records_round_trip() -> None:
    account_id = str(uuid4())
    phone = _phone(account_id)
    headers = _headers(account_id, phone)
    with TestClient(create_app()) as client:
        _, pregnancy_id = _create_pregnancy(client, account_id, phone)
        contraction = _create_record(
            client,
            pregnancy_id,
            headers,
            type="contraction",
            title="宫缩计时 · 2 次",
            structured_data={
                "contractions": [{"start": 0, "duration": 60}, {"start": 300, "duration": 55}],
                "summary": {"pattern": "go"},
            },
        )
        trip = _create_record(
            client,
            pregnancy_id,
            headers,
            type="hospital_trip",
            title="我们出发去医院了",
            content="打车去市妇保",
            structured_data={
                "reason": "contractions",
                "contraction_record_id": contraction.json()["id"],
            },
        )
        private_trip = _create_record(
            client,
            pregnancy_id,
            headers,
            type="hospital_trip",
            visibility="private",
            title="我们出发去医院了",
            structured_data={"reason": "other"},
        )
        made_private = client.patch(
            f"/api/v1/pregnancies/{pregnancy_id}/records/{trip.json()['id']}",
            json={"visibility": "private"},
            headers=headers,
        )
        listed = client.get(
            f"/api/v1/pregnancies/{pregnancy_id}/records",
            params={"type": "hospital_trip"},
            headers=headers,
        )

    assert contraction.status_code == 201, contraction.text
    assert contraction.json()["structured_data"]["summary"]["pattern"] == "early"
    assert contraction.json()["structured_data"]["summary"]["avg_interval_seconds"] == 300
    assert trip.status_code == 201, trip.text
    assert private_trip.status_code == 409, private_trip.text
    assert made_private.status_code == 409, made_private.text
    assert [r["id"] for r in listed.json()["records"]] == [trip.json()["id"]]
```

写之前先看 `_create_record` 的签名，确认它接受 `visibility=` 和 `content=` 关键字参数（`grep -n "def _create_record" -A 25 tests/integration/records/test_records_api.py`）。不接受就照它现有的写法给它补上这两个参数，缺省值保持原样。PATCH 的路径与请求体照文件里已有的可见性修改测试（`grep -n "patch(" tests/integration/records/test_records_api.py`）。

家庭动态：在 `tests/integration` 里找已有的家庭动态测试（`grep -rn "fetal_movement\|胎动" tests/ | grep -i activ`）。有就照它加一条断言：没有标题的 `contraction` 记录在动态里显示为「宫缩」。没有就跳过，`activity.py` 的改动只是两行字典。

- [ ] **Step 5: 运行测试、重新生成契约**

Run: `cd services/api && python3 -m pytest -q && cd ../.. && make contracts && git diff --stat contracts/`
Expected:
- 测试全部 PASS。
- `contracts/public-api/openapi.json` 与 `contracts/agent-tools/openapi.json` 的 `RecordType` 枚举多了 `contraction`、`hospital_trip`。

- [ ] **Step 6: 提交**

```bash
git add services/api contracts/public-api/openapi.json contracts/agent-tools/openapi.json
git commit -m "feat(api): 去医院记录（必须家庭可见）与家庭动态类型名"
```

---

### Task 3: AIM 读宫缩与去医院记录；百科口径

**Files:**
- Modify: `services/agent/agent/tools/list_records.ts:9`
- Modify: `services/agent/agent/instructions.md`（胎动段落之后，约 :93）
- Modify: `services/agent/tests/tools/records.test.ts`
- Modify: `content/encyclopedia/birth.yaml`（`birth.when-to-go` 第二节）、`content/README.md`

**Interfaces:**
- Consumes：Task 1、2 的记录类型与 `summary` 字段名。
- Produces：AIM `list_records` 的 `type` 接受 `contraction`、`hospital_trip`。

- [ ] **Step 1: 写测试（先失败）**

`services/agent/tests/tools/records.test.ts` 末尾加：

```ts
test("AIM can read contraction and hospital trip records but cannot create them", () => {
  type Schema = { safeParse(value: unknown): { success: boolean } };
  const listSchema = listRecords.inputSchema as unknown as Schema;
  const createSchema = createRecord.inputSchema as unknown as Schema;

  assert.equal(listSchema.safeParse({ type: "contraction" }).success, true);
  assert.equal(listSchema.safeParse({ type: "hospital_trip" }).success, true);
  // 宫缩计时要实时按，去医院要本人确认告诉家人：AIM 都不能替用户建。
  assert.equal(createSchema.safeParse({ recordType: "contraction" }).success, false);
  assert.equal(createSchema.safeParse({ recordType: "hospital_trip" }).success, false);
});
```

- [ ] **Step 2: 运行，确认失败**

Run: `cd services/agent && npm test 2>&1 | tail -20`
Expected: 新用例 FAIL（`contraction` 不在枚举里）。

- [ ] **Step 3: 实现**

`list_records.ts` 第 9 行枚举加 `"contraction", "hospital_trip"`：

```ts
    type: z.enum(["symptom", "checkup", "note", "question", "knowledge", "fetal_movement", "memory", "contraction", "hospital_trip"]).optional(),
```

`instructions.md`：在胎动段落（以 "point them to the count screen in the app." 结尾）之后插入一段：

```markdown
When the user mentions contractions, tightening, or thinks labor may be
starting, first check for the conditions that mean going now: waters breaking,
bleeding as heavy as a period, constant severe pain that does not ease, the
baby moving much less, headache with blurred vision or fits, or regular
contractions before 37 weeks. If any applies, your first sentence tells them to
go to the hospital or call 120 now, before anything else. Otherwise read their
recent timings with `list_records` (type `contraction`). Each record is one
timing session made in the app: `summary.last_hour_count`,
`summary.avg_interval_seconds` (start to start) and
`summary.avg_duration_seconds` describe the hour before the last contraction,
and `summary.pattern` is `go` (the 5-1-1 reference is met: about every 5
minutes, about 1 minute each, for an hour), `approaching` (getting regular) or
`early`. 5-1-1 is a reference for a first baby; someone who has given birth
before should leave earlier, around when contractions become regular at about
10 minutes apart, and what their own doctor told them always comes first. Never
say it is too early to go or that they can wait. Before 37 weeks, regular
contractions are a reason to contact the hospital now whatever the pattern
says. A `hospital_trip` record means the family has set off for the hospital;
`reason` says why. You cannot time contractions or create either record; point
them to the contraction timer on the labor page in the app.
```

若 `tests/instructions.test.ts` 对指令全文有长度上限或关键词断言，跑一遍看是否需要同步调整；只放宽与本段相关的断言。

`content/encyclopedia/birth.yaml` 的 `birth.when-to-go` 里，`heading: 规律宫缩时` 的 `text` 整句替换为：

```yaml
        text: 第一次生孩子的常用参考是「5-1-1」：宫缩约 5 分钟一次、每次约 1 分钟、这样持续 1 小时，就该出发。生过孩子的产程可能更快，宫缩变规律（约 10 分钟一次）就联系医院。具体时机请提前问清楚你的产检医生，以医生交代为准。App 里的宫缩计时可以帮你算间隔。
```

`content/README.md`：

1. 在「### 待产科医生复核」列表末尾加一条：

```markdown
- **宫缩计时与去医院时机（2026-10-12）**：百科 `birth.when-to-go`「规律宫缩时」写了 5-1-1 参考和「生过孩子约 10 分钟一次就联系医院」；
  App 宫缩计时页的档位与文案见 `apps/ios/AimApp/Features/Labor/LaborCopy.swift`。其中：未满 37 周 20 分钟 ≥4 次或 1 小时 ≥8 次提示早产，
  单次宫缩超过 3 分钟提示持续剧痛立即就医。请确认与本院宣教一致。
```

2. 在百科「### 审核记录」末尾加一条：

```markdown
- **2026-10-12，分娩模式（Claude）**：`birth.when-to-go`「规律宫缩时」补 5-1-1 参考与经产妇提前出发，仍以医生交代为准。文件保持 `reviewed`，改动未经产品负责人复看。
```

- [ ] **Step 4: 运行测试**

Run:
```bash
cd services/agent && npm test 2>&1 | tail -5
cd ../api && python3 -m pytest tests/contract -q
```
Expected：两边全部 PASS（契约测试守住百科格式）。

- [ ] **Step 5: 提交**

```bash
git add services/agent content
git commit -m "feat(agent): AIM 读宫缩计时与去医院记录；百科补 5-1-1 参考"
```

---

### Task 4: iOS 两种新记录类型贯通

**Files:**
- Modify: `apps/ios/AimApp/Features/Records/RecordModels.swift`
- Modify: `apps/ios/AimApp/Generated/OpenAPI/Models.swift`
- Modify: `apps/ios/AimApp/Clients/BusinessAPIClient/BusinessRepository.swift:681-686`
- Modify: `apps/ios/AimApp/Features/Records/RecordsView.swift`、`RecordDetailView.swift`、`RecordComposerView.swift`
- Test: 在 `apps/ios/AimApp/Tests/` 里已有的记录解码测试文件中加用例（`grep -ln "fetal_movement" apps/ios/AimApp/Tests/` 找到胎动解码用例所在文件，加在它旁边）

**Interfaces:**
- Produces（Task 5–9 使用）：

```swift
enum RecordType { ... case contraction, hospitalTrip ... }   // 原始值 "contraction"、"hospital_trip"

struct ContractionEntry: Codable, Equatable, Sendable {
    let start: Int      // 距第一次开始的秒数
    let duration: Int   // 持续秒数
}
enum ContractionPattern: String, Codable, Sendable { case early, approaching, go }
struct ContractionSummary: Codable, Equatable, Sendable {
    let count: Int
    let lastHourCount: Int
    let avgIntervalSeconds: Int?
    let avgDurationSeconds: Int
    let pattern: ContractionPattern
}
struct ContractionRecordData: Equatable, Sendable {
    let contractions: [ContractionEntry]
    /// 服务端算的；新建时客户端不发。
    var summary: ContractionSummary?
}

enum HospitalTripReason: String, CaseIterable, Sendable {
    case contractions, waterBroke = "water_broke", bleeding, fetalMovement = "fetal_movement", scheduled, other
    var displayName: String { ... }
}
struct HospitalTripRecordData: Equatable, Sendable {
    let reason: HospitalTripReason
    var contractionRecordID: UUID?
}

enum RecordStructuredData { ... case contraction(ContractionRecordData), hospitalTrip(HospitalTripRecordData) ... }
```

- [ ] **Step 1: 写解码测试（先失败）**

在胎动解码用例所在的测试文件里，照它的写法（它是怎么构造 JSON、怎么调解码的，就怎么写）加两条：

```swift
    func testDecodesContractionRecordWithServerSummary() throws {
        let json = """
        {"contractions": [{"start": 0, "duration": 60}, {"start": 300, "duration": 55}],
         "summary": {"count": 2, "last_hour_count": 2, "avg_interval_seconds": 300,
                     "avg_duration_seconds": 58, "pattern": "early"}}
        """
        let dto = try JSONDecoder().decode(APIRecordStructuredDataDTO.self, from: Data(json.utf8))
        guard case let .contraction(data) = dto.recordData(for: .contraction) else {
            return XCTFail("应当解出宫缩计时")
        }
        XCTAssertEqual(data.contractions, [ContractionEntry(start: 0, duration: 60), ContractionEntry(start: 300, duration: 55)])
        XCTAssertEqual(data.summary?.pattern, .early)
        XCTAssertEqual(data.summary?.avgIntervalSeconds, 300)
    }

    func testDecodesHospitalTripAndEncodesWithoutSummary() throws {
        let linked = UUID()
        let json = """
        {"reason": "water_broke", "contraction_record_id": "\(linked.uuidString.lowercased())"}
        """
        let dto = try JSONDecoder().decode(APIRecordStructuredDataDTO.self, from: Data(json.utf8))
        guard case let .hospitalTrip(data) = dto.recordData(for: .hospitalTrip) else {
            return XCTFail("应当解出去医院")
        }
        XCTAssertEqual(data.reason, .waterBroke)
        XCTAssertEqual(data.contractionRecordID, linked)

        // 新建宫缩记录时不发 summary：那是服务端算的。
        let encoded = try JSONEncoder().encode(APIRecordStructuredDataDTO(recordData: .contraction(
            ContractionRecordData(contractions: [ContractionEntry(start: 0, duration: 60)], summary: nil))))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["summary"])
        XCTAssertNotNil(object["contractions"])
    }

    func testRecordTypeRoundTripsNewRawValues() {
        XCTAssertEqual(RecordType(rawValue: "contraction"), .contraction)
        XCTAssertEqual(RecordType(rawValue: "hospital_trip"), .hospitalTrip)
        XCTAssertEqual(RecordType.hospitalTrip.rawValue, "hospital_trip")
    }
```

`RecordType` 是自定义的 `init(from:)`、`rawValue`，若它不是 `RawRepresentable`，最后一条改用它实际的解码、编码方式断言（照文件里已有的 `fetal_movement` 写法）。

- [ ] **Step 2: 运行，确认编译失败**

Run: 按 Global Constraints 的命令跑这个测试类。
Expected: 编译失败，`contraction` 未定义。

- [ ] **Step 3: 实现**

`RecordModels.swift`：
1. `RecordType`：加 `case contraction`、`case hospitalTrip`，同时补进解码（`"contraction"`、`"hospital_trip"`）、`rawValue`、`displayName`。
2. `canEditInComposer` 改为 `![.fetalMovement, .memory, .contraction, .hospitalTrip].contains(self)`。
3. 加上面 Interfaces 里列出的类型。`HospitalTripReason.displayName` 依次为：「规律宫缩」「破水」「出血」「胎动少了」「按医生安排入院」「其他」。
4. `RecordStructuredData` 加两个 case。

`Generated/OpenAPI/Models.swift` 的 `APIRecordStructuredDataDTO`：
1. 加字段：

```swift
    let contractions: [ContractionEntry]?
    let summary: ContractionSummaryDTO?
    let contractionRecordID: String?
```

`reason` 已有，是 knowledge 用的，同名字段直接复用。

2. `ContractionSummaryDTO` 放在同文件，作用是把 snake_case 键名映射到 `ContractionSummary`：

```swift
struct ContractionSummaryDTO: Codable, Sendable {
    let count: Int
    let lastHourCount: Int
    let avgIntervalSeconds: Int?
    let avgDurationSeconds: Int
    let pattern: String

    enum CodingKeys: String, CodingKey {
        case count, pattern
        case lastHourCount = "last_hour_count"
        case avgIntervalSeconds = "avg_interval_seconds"
        case avgDurationSeconds = "avg_duration_seconds"
    }

    var model: ContractionSummary? {
        ContractionPattern(rawValue: pattern).map {
            ContractionSummary(count: count, lastHourCount: lastHourCount,
                               avgIntervalSeconds: avgIntervalSeconds,
                               avgDurationSeconds: avgDurationSeconds, pattern: $0)
        }
    }
}
```

3. 编解码：
   - `init(...)` 参数、赋值、`CodingKeys` 都补上新字段，其中加 `case contractions, summary` 和 `case contractionRecordID = "contraction_record_id"`。
   - `recordData(for:)` 加：

```swift
        case .contraction:
            guard let contractions, !contractions.isEmpty else { return .unknown }
            return .contraction(ContractionRecordData(contractions: contractions, summary: summary?.model))
        case .hospitalTrip:
            guard let reason, let value = HospitalTripReason(rawValue: reason) else { return .unknown }
            return .hospitalTrip(HospitalTripRecordData(
                reason: value, contractionRecordID: contractionRecordID.flatMap(UUID.init(uuidString:))))
```

   - `init(recordData:)` 加：

```swift
        case let .contraction(data):
            // summary 由服务端计算，不发。
            self.init(contractions: data.contractions)
        case let .hospitalTrip(data):
            self.init(reason: data.reason.rawValue,
                      contractionRecordID: data.contractionRecordID?.uuidString.lowercased())
```

`ContractionEntry` 的键名就是 `start`、`duration`，自动合成的 Codable 即可。

`BusinessRepository.swift` 的 `validate(_:)`：在配对列表里加 `(.contraction, .contraction), (.hospitalTrip, .hospitalTrip)`。

`RecordsView.swift`、`RecordDetailView.swift`、`RecordComposerView.swift`：编译器会指出所有不完整的 `switch`，逐个补上。

- `RecordsView`：
  - 类型名分别为「宫缩」「去医院」。
  - 图标分别为 `"waveform.path.ecg"`、`"car"`。
  - 摘要：宫缩用 `ContractionFormat.summary(data)`（Task 5 定义；本任务先写成 `"\(data.contractions.count) 次宫缩"`，Task 5 再替换）；去医院用 `data.reason.displayName`。
  - 新建入口的文案处（第 61 行附近，胎动是「数胎动」），两种类型都不出现在新建入口里，照 `.fetalMovement` 的处理方式归类。
- `RecordDetailView`：

```swift
        case let .contraction(data):
            Section("宫缩计时") {
                LabeledContent("次数", value: "\(data.contractions.count) 次")
                if let summary = data.summary {
                    LabeledContent("最近 1 小时", value: "\(summary.lastHourCount) 次")
                    if let interval = summary.avgIntervalSeconds {
                        LabeledContent("平均间隔", value: ContractionFormat.seconds(interval))
                    }
                    LabeledContent("平均持续", value: ContractionFormat.seconds(summary.avgDurationSeconds))
                }
            }
            Section("逐次") {
                ForEach(Array(data.contractions.enumerated()), id: \.offset) { index, entry in
                    LabeledContent(
                        record.occurredAt.addingTimeInterval(TimeInterval(entry.start))
                            .formatted(date: .omitted, time: .shortened),
                        value: "持续 \(ContractionFormat.seconds(entry.duration))")
                }
            }
        case let .hospitalTrip(data):
            Section("去医院") {
                LabeledContent("原因", value: data.reason.displayName)
                LabeledContent("出发时间", value: record.occurredAt.formatted(date: .abbreviated, time: .shortened))
                if let note = record.content, !note.isEmpty { Text(note) }
                if data.contractionRecordID != nil {
                    Text("附带了出发前的宫缩计时，可在档案的宫缩记录里查看。").foregroundStyle(.secondary)
                }
            }
```

  `ContractionFormat.seconds` 在 Task 5 定义。本任务先在 `RecordModels.swift` 末尾放一个最小版本，Task 5 把它移进 `ContractionModels.swift` 并删掉这里的：

```swift
enum ContractionFormat {
    /// 「45 秒」「4 分 50 秒」「5 分钟」。
    static func seconds(_ value: Int) -> String {
        guard value >= 60 else { return "\(value) 秒" }
        let minutes = value / 60, rest = value % 60
        return rest == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(rest) 秒"
    }
}
```

- `RecordComposerView`：三处 `switch` 都把两个新 case 和 `.fetalMovement` 并列。

- [ ] **Step 4: 运行测试**

Run: 跑这个测试类，再跑一遍全部单元测试（`-only-testing:AimAppTests`）。
Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add apps/ios/AimApp
git commit -m "feat(ios): 宫缩计时与去医院记录类型贯通"
```

---

### Task 5: 宫缩计时器与档位计算（纯数据）

**Files:**
- Create: `apps/ios/AimApp/Features/Labor/ContractionModels.swift`（编号 180）
- Test: `apps/ios/AimApp/Tests/ContractionModelsTests.swift`（编号 187）
- Modify: `apps/ios/AimApp/Features/Records/RecordModels.swift`（移走临时的 `ContractionFormat`）、`RecordsView.swift`（摘要改用 `ContractionFormat.summary`）
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes：Task 4 的 `ContractionEntry`、`ContractionSummary`、`ContractionPattern`、`ContractionRecordData`。
- Produces：

```swift
struct ContractionTimer: Codable, Equatable, Sendable {
    struct Span: Codable, Equatable, Sendable { let start: Date; var end: Date? }
    static let maxDuration: TimeInterval = 600
    static let longRunning: TimeInterval = 180
    static let quietAfter: TimeInterval = 1200
    static let staleAfter: TimeInterval = 21_600
    private(set) var spans: [Span]
    init()
    var startedAt: Date? { get }
    var isContracting: Bool { get }
    var completed: [Span] { get }           // 已结束的
    var lastEnd: Date? { get }
    enum ToggleResult: Equatable, Sendable { case began, ended, ignored }
    mutating func toggle(at now: Date) -> ToggleResult
    mutating func removeLast()
    mutating func capRunning(at now: Date)  // 进行中超过 600 秒的截断为 600 秒并结束
    func isStale(at now: Date) -> Bool       // 没在宫缩、有已结束的、最后结束距今 > 6 小时
    func entries() -> [ContractionEntry]     // 只含已结束的
}

enum ContractionStage: Equatable, Sendable { case early, approaching, go, pretermAlert }

struct ContractionStatus: Equatable, Sendable {
    let stage: ContractionStage
    let summary: ContractionSummary?       // 没有已结束的宫缩时为 nil
    let quietMinutes: Int?                 // 停顿回落时有值
    let runningSeconds: Int?               // 宫缩中有值
    var isLongRunning: Bool { (runningSeconds ?? 0) > Int(ContractionTimer.longRunning) }
}

enum ContractionMath {
    static func summary(_ entries: [ContractionEntry]) -> ContractionSummary
    static func status(_ timer: ContractionTimer, at now: Date, weeks: Int?) -> ContractionStatus
}

struct ContractionResult: Codable, Equatable, Sendable {
    let id: UUID                    // 本地队列去重用，不发给后端
    let startedAt: Date
    let entries: [ContractionEntry]
    var title: String { get }       // 「宫缩计时 · 14 次 · 约 4 分 50 秒一次」
    var draft: RecordDraft { get }
}

struct ContractionSession: Identifiable, Equatable, Sendable {
    let id: UUID; let startedAt: Date; let data: ContractionRecordData
    init?(record: RecordItem)
}

enum ContractionFormat {
    static func seconds(_ value: Int) -> String
    static func summary(_ data: ContractionRecordData) -> String
}
```

- [ ] **Step 1: 写测试（先失败）**

`apps/ios/AimApp/Tests/ContractionModelsTests.swift`：

```swift
import XCTest
@testable import AimApp

final class ContractionModelsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // 与 contracts/fixtures/contraction-summary-vectors.json 保持一致，改那边要同步改这里。
    private let vectorsJSON = #"""
    <<把 contracts/fixtures/contraction-summary-vectors.json 的完整内容原样粘贴到这里>>
    """#

    private struct VectorFile: Decodable {
        struct Vector: Decodable {
            let name: String
            let contractions: [[Int]]
            let expected: Expected
        }
        struct Expected: Decodable {
            let count: Int
            let last_hour_count: Int
            let avg_interval_seconds: Int?
            let avg_duration_seconds: Int
            let pattern: String
        }
        let vectors: [Vector]
    }

    func testSummaryMatchesSharedVectors() throws {
        let file = try JSONDecoder().decode(VectorFile.self, from: Data(vectorsJSON.utf8))
        XCTAssertFalse(file.vectors.isEmpty)
        for vector in file.vectors {
            let entries = vector.contractions.map { ContractionEntry(start: $0[0], duration: $0[1]) }
            let summary = ContractionMath.summary(entries)
            XCTAssertEqual(summary.count, vector.expected.count, vector.name)
            XCTAssertEqual(summary.lastHourCount, vector.expected.last_hour_count, vector.name)
            XCTAssertEqual(summary.avgIntervalSeconds, vector.expected.avg_interval_seconds, vector.name)
            XCTAssertEqual(summary.avgDurationSeconds, vector.expected.avg_duration_seconds, vector.name)
            XCTAssertEqual(summary.pattern.rawValue, vector.expected.pattern, vector.name)
        }
    }

    // MARK: - 计时器

    func testToggleBeginsAndEndsAContraction() {
        var timer = ContractionTimer()
        XCTAssertEqual(timer.toggle(at: t0), .began)
        XCTAssertTrue(timer.isContracting)
        XCTAssertEqual(timer.toggle(at: t0 + 62.7), .ended)
        XCTAssertFalse(timer.isContracting)
        XCTAssertEqual(timer.entries(), [ContractionEntry(start: 0, duration: 62)])
    }

    func testEndingWithinOneSecondIsTreatedAsAMistap() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        XCTAssertEqual(timer.toggle(at: t0 + 0.5), .ignored)
        XCTAssertTrue(timer.spans.isEmpty, "不到 1 秒就结束是误触，这一次整个取消")
    }

    func testBeginningRightAfterTheLastEndIsIgnored() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        _ = timer.toggle(at: t0 + 60)
        XCTAssertEqual(timer.toggle(at: t0 + 60.4), .ignored)
        XCTAssertEqual(timer.toggle(at: t0 + 300), .began)
    }

    func testEntriesAreOffsetsFromTheFirstStartAndNeverOverlap() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0 + 0.9)
        _ = timer.toggle(at: t0 + 60.2)
        _ = timer.toggle(at: t0 + 61.3)
        _ = timer.toggle(at: t0 + 120.8)
        let entries = timer.entries()
        XCTAssertEqual(entries.first?.start, 0)
        for (previous, next) in zip(entries, entries.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next.start, previous.start + previous.duration)
        }
    }

    func testEntriesSkipTheRunningContraction() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        _ = timer.toggle(at: t0 + 60)
        _ = timer.toggle(at: t0 + 300)
        XCTAssertEqual(timer.entries().count, 1)
    }

    func testRemoveLastCancelsRunningOrDeletesTheLastCompleted() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        _ = timer.toggle(at: t0 + 60)
        _ = timer.toggle(at: t0 + 300)
        timer.removeLast()
        XCTAssertFalse(timer.isContracting)
        XCTAssertEqual(timer.spans.count, 1)
        timer.removeLast()
        XCTAssertTrue(timer.spans.isEmpty)
    }

    func testCapRunningTruncatesAfterTenMinutes() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        timer.capRunning(at: t0 + 300)
        XCTAssertTrue(timer.isContracting, "不到 10 分钟不截断")
        timer.capRunning(at: t0 + 3600)
        XCTAssertFalse(timer.isContracting)
        XCTAssertEqual(timer.entries(), [ContractionEntry(start: 0, duration: 600)])
    }

    func testStaleAfterSixHoursSinceTheLastEnd() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        _ = timer.toggle(at: t0 + 60)
        XCTAssertFalse(timer.isStale(at: t0 + 60 + 21_600))
        XCTAssertTrue(timer.isStale(at: t0 + 60 + 21_601))
    }

    func testTimerSurvivesEncoding() throws {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        let decoded = try JSONDecoder().decode(ContractionTimer.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(decoded, timer)
    }

    // MARK: - 实时档位

    /// 每 interval 秒一次、每次 duration 秒，共 count 次，从 t0 开始。
    private func timer(count: Int, interval: TimeInterval, duration: TimeInterval) -> ContractionTimer {
        var timer = ContractionTimer()
        for i in 0..<count {
            let start = t0 + Double(i) * interval
            _ = timer.toggle(at: start)
            _ = timer.toggle(at: start + duration)
        }
        return timer
    }

    func testLiveStatusMatchesTheStoredSummaryRightAfterTheLastContraction() {
        let timer = timer(count: 12, interval: 300, duration: 55)
        let status = ContractionMath.status(timer, at: t0 + 3300 + 55, weeks: 39)
        XCTAssertEqual(status.stage, .go)
        XCTAssertEqual(status.summary, ContractionMath.summary(timer.entries()))
    }

    func testLongQuietFallsBackToEarly() {
        let timer = timer(count: 12, interval: 300, duration: 55)
        let lastEnd = t0 + 3300 + 55
        XCTAssertEqual(ContractionMath.status(timer, at: lastEnd + 1200, weeks: 39).stage, .go)
        let quiet = ContractionMath.status(timer, at: lastEnd + 1201, weeks: 39)
        XCTAssertEqual(quiet.stage, .early)
        XCTAssertEqual(quiet.quietMinutes, 20)
    }

    func testPretermAlertForFourInTwentyMinutes() {
        let timer = timer(count: 4, interval: 300, duration: 40)
        let now = t0 + 900 + 40
        XCTAssertEqual(ContractionMath.status(timer, at: now, weeks: 35).stage, .pretermAlert)
        XCTAssertNotEqual(ContractionMath.status(timer, at: now, weeks: 37).stage, .pretermAlert)
        XCTAssertNotEqual(ContractionMath.status(timer, at: now, weeks: nil).stage, .pretermAlert,
                          "不知道孕周时不猜")
    }

    func testPretermAlertForEightInAnHour() {
        let timer = timer(count: 8, interval: 480, duration: 40)
        let now = t0 + 7 * 480 + 40
        XCTAssertEqual(ContractionMath.status(timer, at: now, weeks: 33).stage, .pretermAlert)
    }

    func testRunningContractionReportsSecondsAndLongRunning() {
        var timer = ContractionTimer()
        _ = timer.toggle(at: t0)
        XCTAssertEqual(ContractionMath.status(timer, at: t0 + 30, weeks: 39).runningSeconds, 30)
        XCTAssertFalse(ContractionMath.status(timer, at: t0 + 180, weeks: 39).isLongRunning)
        XCTAssertTrue(ContractionMath.status(timer, at: t0 + 181, weeks: 39).isLongRunning)
        XCTAssertNil(ContractionMath.status(timer, at: t0 + 30, weeks: 39).summary, "还没有结束的宫缩")
    }

    // MARK: - 结果与格式

    func testResultDraftAndTitle() {
        let result = ContractionResult(
            id: UUID(), startedAt: t0,
            entries: (0..<12).map { ContractionEntry(start: $0 * 290, duration: 60) })
        XCTAssertEqual(result.title, "宫缩计时 · 12 次 · 约 4 分 50 秒一次")
        XCTAssertEqual(result.draft.type, .contraction)
        XCTAssertEqual(result.draft.visibility, .family)
        XCTAssertEqual(result.draft.occurredAt, t0)
        XCTAssertEqual(ContractionResult(id: UUID(), startedAt: t0,
                                         entries: [ContractionEntry(start: 0, duration: 60)]).title,
                       "宫缩计时 · 1 次")
    }

    func testFormatSeconds() {
        XCTAssertEqual(ContractionFormat.seconds(45), "45 秒")
        XCTAssertEqual(ContractionFormat.seconds(290), "4 分 50 秒")
        XCTAssertEqual(ContractionFormat.seconds(300), "5 分钟")
    }
}
```

`vectorsJSON` 必须原样粘贴 Step 1 那个 JSON 文件的全部内容（Task 1 已写好），不能留占位。

- [ ] **Step 2: 登记工程文件，运行，确认失败**

在 `project.pbxproj` 登记两个新文件：
- `Features/Labor/ContractionModels.swift` 用编号 180，进 App target。group 照 `FetalMovement` 的做法新建一个 `Labor` group，挂在 `Features` group 下。
- `Tests/ContractionModelsTests.swift` 用编号 187，进测试 target。

Run: 跑 `ContractionModelsTests`。
Expected: 编译失败，`ContractionTimer` 未定义。

- [ ] **Step 3: 实现**

`apps/ios/AimApp/Features/Labor/ContractionModels.swift`：

```swift
import Foundation

/// 一次宫缩计时：每次宫缩的开始与结束时刻。
///
/// 纯数据、不碰计时器：所有判断以时间戳和传入的「现在」计算。
/// App 被挂起或杀掉后，从本地恢复同一个值就能接着算。
struct ContractionTimer: Codable, Equatable, Sendable {
    struct Span: Codable, Equatable, Sendable {
        let start: Date
        var end: Date?
    }

    /// 单次宫缩最长记 10 分钟：再长多半是忘了按结束，后端也不收。
    static let maxDuration: TimeInterval = 600
    /// 超过 3 分钟还没结束要提示「持续剧痛不缓解请立即去医院」。
    static let longRunning: TimeInterval = 180
    /// 20 分钟没有宫缩，实时档位回落。
    static let quietAfter: TimeInterval = 1200
    /// 最后一次结束超过 6 小时还没保存，先让用户决定保存还是丢弃。
    static let staleAfter: TimeInterval = 21_600
    /// 不到 1 秒的开始或结束都当误触。
    static let minimumGap: TimeInterval = 1

    private(set) var spans: [Span] = []

    init() {}

    var startedAt: Date? { spans.first?.start }
    var isContracting: Bool { spans.last.map { $0.end == nil } ?? false }
    var completed: [Span] { spans.filter { $0.end != nil } }
    var lastEnd: Date? { completed.last?.end }

    enum ToggleResult: Equatable, Sendable { case began, ended, ignored }

    mutating func toggle(at now: Date) -> ToggleResult {
        if isContracting, let start = spans.last?.start {
            guard now.timeIntervalSince(start) >= Self.minimumGap else {
                spans.removeLast()
                return .ignored
            }
            spans[spans.count - 1].end = min(now, start + Self.maxDuration)
            return .ended
        }
        if let lastEnd, now.timeIntervalSince(lastEnd) < Self.minimumGap { return .ignored }
        spans.append(Span(start: now, end: nil))
        return .began
    }

    /// 误按了：宫缩中就取消这一次，否则删掉最后一次。
    mutating func removeLast() {
        guard !spans.isEmpty else { return }
        spans.removeLast()
    }

    /// 宫缩中被系统杀掉、很久才回来：超过 10 分钟的截断为 10 分钟并结束。
    mutating func capRunning(at now: Date) {
        guard isContracting, let start = spans.last?.start,
              now.timeIntervalSince(start) > Self.maxDuration else { return }
        spans[spans.count - 1].end = start + Self.maxDuration
    }

    func isStale(at now: Date) -> Bool {
        guard !isContracting, let lastEnd else { return false }
        return now.timeIntervalSince(lastEnd) > Self.staleAfter
    }

    /// 存档用：只含已结束的宫缩。开始与结束都按距第一次开始的整秒向下取整，
    /// 持续 = 结束秒 − 开始秒（至少 1），这样取整后也不会和下一次重叠。
    func entries() -> [ContractionEntry] {
        guard let origin = completed.first?.start else { return [] }
        return completed.compactMap { span in
            guard let end = span.end else { return nil }
            let start = Int(span.start.timeIntervalSince(origin).rounded(.down))
            let finish = Int(end.timeIntervalSince(origin).rounded(.down))
            return ContractionEntry(start: start, duration: min(max(1, finish - start), Int(Self.maxDuration)))
        }
    }
}

enum ContractionStage: Equatable, Sendable { case early, approaching, go, pretermAlert }

struct ContractionStatus: Equatable, Sendable {
    let stage: ContractionStage
    let summary: ContractionSummary?
    let quietMinutes: Int?
    let runningSeconds: Int?

    var isLongRunning: Bool { (runningSeconds ?? 0) > Int(ContractionTimer.longRunning) }
}

/// 5-1-1 档位。与服务端 `aim_api.contexts.records.domain.contraction` 同一套规则，
/// 两边共用 contracts/fixtures/contraction-summary-vectors.json 的测试向量。
enum ContractionMath {
    static let goMaxInterval: Double = 300
    static let goMinDuration: Double = 50
    static let goMinSpan = 3300
    static let approachingMinCount = 4
    static let approachingMaxInterval: Double = 420
    static let pretermWeeks = 37

    static func summary(_ entries: [ContractionEntry]) -> ContractionSummary {
        guard let latest = entries.last?.start else {
            return ContractionSummary(count: 0, lastHourCount: 0, avgIntervalSeconds: nil,
                                      avgDurationSeconds: 0, pattern: .early)
        }
        let hour = entries.filter { $0.start >= latest - 3600 }
        let half = entries.filter { $0.start >= latest - 1800 }
        let hourInterval = averageInterval(hour.map(\.start))
        let hourDuration = Double(hour.map(\.duration).reduce(0, +)) / Double(hour.count)
        let halfInterval = averageInterval(half.map(\.start))

        var pattern = ContractionPattern.early
        if let hourInterval, hourInterval <= goMaxInterval, hourDuration >= goMinDuration,
           let first = hour.first?.start, latest - first >= goMinSpan {
            pattern = .go
        } else if half.count >= approachingMinCount, let halfInterval, halfInterval <= approachingMaxInterval {
            pattern = .approaching
        }
        return ContractionSummary(
            count: entries.count, lastHourCount: hour.count,
            avgIntervalSeconds: hourInterval.map { Int($0.rounded()) },
            avgDurationSeconds: Int(hourDuration.rounded()), pattern: pattern)
    }

    static func status(_ timer: ContractionTimer, at now: Date, weeks: Int?) -> ContractionStatus {
        let entries = timer.entries()
        let summary = entries.isEmpty ? nil : summary(entries)
        let running = timer.isContracting
            ? timer.spans.last.map { max(0, Int(now.timeIntervalSince($0.start).rounded(.down))) }
            : nil

        // 早产：以现在为准数最近 20 / 60 分钟开始的宫缩（含正在进行的这一次）。
        if let weeks, weeks < pretermWeeks {
            let starts = timer.spans.map(\.start)
            let inTwenty = starts.filter { now.timeIntervalSince($0) <= 1200 }.count
            let inHour = starts.filter { now.timeIntervalSince($0) <= 3600 }.count
            if inTwenty >= 4 || inHour >= 8 {
                return ContractionStatus(stage: .pretermAlert, summary: summary, quietMinutes: nil, runningSeconds: running)
            }
        }

        // 停顿回落：空档不在窗口的平均间隔里，档位不会自己回落，单独判断。
        if !timer.isContracting, let lastEnd = timer.lastEnd {
            let quiet = now.timeIntervalSince(lastEnd)
            if quiet > ContractionTimer.quietAfter {
                return ContractionStatus(stage: .early, summary: summary,
                                         quietMinutes: Int(quiet / 60), runningSeconds: nil)
            }
        }

        let stage: ContractionStage = switch summary?.pattern {
        case .go: .go
        case .approaching: .approaching
        case .early, .none: .early
        }
        return ContractionStatus(stage: stage, summary: summary, quietMinutes: nil, runningSeconds: running)
    }

    private static func averageInterval(_ starts: [Int]) -> Double? {
        guard starts.count >= 2, let first = starts.first, let last = starts.last else { return nil }
        return Double(last - first) / Double(starts.count - 1)
    }
}

/// 结束计时后待保存的一次计时。`id` 只用于本地队列去重。
struct ContractionResult: Codable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let entries: [ContractionEntry]

    var recordData: ContractionRecordData { ContractionRecordData(contractions: entries, summary: nil) }

    /// 家庭动态直接显示它：「爸爸 记了「宫缩计时 · 14 次 · 约 4 分 50 秒一次」」。
    var title: String {
        "宫缩计时 · " + ContractionFormat.summary(
            ContractionRecordData(contractions: entries, summary: ContractionMath.summary(entries)))
    }

    var draft: RecordDraft {
        RecordDraft(type: .contraction, occurredAt: startedAt, visibility: .family,
                    title: title, content: nil, structuredData: .contraction(recordData))
    }
}

/// 档案里的一次宫缩计时。
struct ContractionSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let data: ContractionRecordData

    init?(record: RecordItem) {
        guard case let .contraction(data) = record.structuredData else { return nil }
        id = record.id
        startedAt = record.occurredAt
        self.data = data
    }
}

enum ContractionFormat {
    /// 「45 秒」「4 分 50 秒」「5 分钟」。
    static func seconds(_ value: Int) -> String {
        guard value >= 60 else { return "\(value) 秒" }
        let minutes = value / 60, rest = value % 60
        return rest == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(rest) 秒"
    }

    /// 「14 次 · 约 4 分 50 秒一次」；只有一次时只说次数。
    static func summary(_ data: ContractionRecordData) -> String {
        let summary = data.summary ?? ContractionMath.summary(data.contractions)
        guard let interval = summary.avgIntervalSeconds else { return "\(summary.count) 次" }
        return "\(summary.count) 次 · 约 \(seconds(interval))一次"
    }
}
```

注意 `title` 期望是「约 4 分 50 秒一次」：`seconds(290)` 返回「4 分 50 秒」，拼接时中间不加空格。

然后：
- 删掉 Task 4 放在 `RecordModels.swift` 末尾的临时 `ContractionFormat`。
- `RecordsView` 的宫缩摘要改为 `ContractionFormat.summary(data)`。

- [ ] **Step 4: 运行测试**

Run: 跑 `ContractionModelsTests`，再跑全部单元测试。
Expected: 全部 PASS。向量不过时，先对照 Task 1 Step 1 的手算核对实现，不改向量。

- [ ] **Step 5: 提交**

```bash
git add apps/ios/AimApp apps/ios/AimApp.xcodeproj/project.pbxproj
git commit -m "feat(ios): 宫缩计时器与 5-1-1 档位计算"
```

---

### Task 6: ContractionStore

**Files:**
- Create: `apps/ios/AimApp/Features/Labor/ContractionStore.swift`（编号 181）
- Test: `apps/ios/AimApp/Tests/ContractionStoreTests.swift`（编号 188）
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes：Task 5 的 `ContractionTimer`、`ContractionResult`、`ContractionSession`、`ContractionMath`。`BusinessRepositoryProtocol` 的 `createRecord(draft:) async throws -> RecordItem`、`fetchRecords(type:) async throws -> RecordSnapshot`、`deleteRecord(recordID:) async throws`。先 `grep -n "func createRecord\|func fetchRecords\|func deleteRecord" apps/ios/AimApp/Clients/BusinessAPIClient/BusinessRepository.swift` 确认签名，不一致就以实际签名为准。
- Produces：

```swift
@MainActor @Observable final class ContractionStore {
    var repository: BusinessRepositoryProtocol?
    var clock: () -> Date
    /// 孕周，由 App 在首页数据加载后设置；用于早产警示。
    var gestationalWeeks: Int?
    private(set) var active: ContractionTimer?
    private(set) var unsaved: [ContractionResult]
    private(set) var sessions: [ContractionSession]
    private(set) var isSaving: Bool
    var errorMessage: String?

    init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default)
    func bind(accountID: UUID, pregnancyID: UUID)
    func unbind()
    func load() async
    var status: ContractionStatus? { get }          // active 为 nil 时为 nil；按 clock() 和 gestationalWeeks 算
    var needsStaleDecision: Bool { get }             // active 已陈旧（isStale）
    @discardableResult func toggle() -> ContractionTimer.ToggleResult
    func removeLast()
    func resumeAfterLaunch()                          // 截断超过 10 分钟的进行中宫缩
    /// 结束计时并保存：没有已结束的宫缩时返回 nil 且什么都不做。
    /// 保存成功时 savedRecordID 为新记录的 id。
    func finish() async -> (result: ContractionResult, savedRecordID: UUID?)?
    func discardActive()
    @discardableResult func saveUnsaved() async -> Bool
    var latest: ContractionSession? { get }
}
```

- [ ] **Step 1: 写测试（先失败）**

先看 `apps/ios/AimApp/Tests/FetalMovementStoreTests.swift` 里的假仓库是怎么写的（`grep -n "class .*Repository\|final class" apps/ios/AimApp/Tests/FetalMovementStoreTests.swift`）。若有可复用的通用假仓库（如 `RecordingRepository`、`MockBusinessRepository`），直接用；它需要支持：
- 让 `createRecord` 失败，或返回一个 `RecordItem`；
- 记录收到的 drafts；
- `fetchRecords` 返回预设的记录。

没有就在测试文件里照 FetalMovementStoreTests 的假仓库写一个同样的。

`apps/ios/AimApp/Tests/ContractionStoreTests.swift`：

```swift
import XCTest
@testable import AimApp

@MainActor
final class ContractionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private let account = UUID(), pregnancy = UUID()

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ContractionStoreTests.\(UUID().uuidString)")
    }

    private func makeStore(repository: BusinessRepositoryProtocol? = nil) -> ContractionStore {
        let store = ContractionStore(defaults: defaults, notificationCenter: NotificationCenter())
        store.clock = { [unowned self] in self.now }
        store.repository = repository
        store.bind(accountID: account, pregnancyID: pregnancy)
        return store
    }

    private func contract(_ store: ContractionStore, seconds: TimeInterval = 60, then rest: TimeInterval = 240) {
        store.toggle(); now += seconds
        store.toggle(); now += rest
    }

    func testUnboundStoreIgnoresToggles() {
        let store = ContractionStore(defaults: defaults, notificationCenter: NotificationCenter())
        XCTAssertEqual(store.toggle(), .ignored)
        XCTAssertNil(store.active)
    }

    func testActiveTimerIsRestoredForTheSameScopeOnly() {
        let first = makeStore()
        contract(first)
        let again = makeStore()
        XCTAssertEqual(again.active, first.active, "同一账号与孕期能接着计时")

        let other = ContractionStore(defaults: defaults, notificationCenter: NotificationCenter())
        other.bind(accountID: UUID(), pregnancyID: pregnancy)
        XCTAssertNil(other.active, "换了账号看不到别人的计时")
    }

    func testFinishSavesAndReturnsTheNewRecordID() async {
        let repository = <<假仓库，createRecord 成功并返回 id 为 savedID 的 RecordItem>>
        let store = makeStore(repository: repository)
        contract(store); contract(store)
        let outcome = await store.finish()
        XCTAssertEqual(outcome?.result.entries.count, 2)
        XCTAssertNotNil(outcome?.savedRecordID)
        XCTAssertNil(store.active)
        XCTAssertTrue(store.unsaved.isEmpty)
        XCTAssertEqual(<<假仓库收到的 drafts>>.first?.type, .contraction)
    }

    func testFinishWithoutACompletedContractionDoesNothing() async {
        let store = makeStore()
        store.toggle()
        let outcome = await store.finish()
        XCTAssertNil(outcome)
        XCTAssertNotNil(store.active, "宫缩还在进行中，不能把计时丢掉")
    }

    func testFinishDropsTheRunningContractionButKeepsCompletedOnes() async {
        let store = makeStore(repository: <<成功的假仓库>>)
        contract(store)
        store.toggle()  // 第二次开始了但没结束
        let outcome = await store.finish()
        XCTAssertEqual(outcome?.result.entries.count, 1)
    }

    func testFailedSaveIsKeptLocallyAndRetried() async {
        let repository = <<createRecord 先失败的假仓库>>
        let store = makeStore(repository: repository)
        contract(store)
        let outcome = await store.finish()
        XCTAssertNil(outcome?.savedRecordID)
        XCTAssertEqual(store.unsaved.count, 1)
        XCTAssertEqual(store.errorMessage, "没保存上，重试")

        // 重新绑定（模拟重启）后队列还在。
        XCTAssertEqual(makeStore().unsaved.count, 1)

        <<让假仓库改为成功>>
        let saved = await store.saveUnsaved()
        XCTAssertTrue(saved)
        XCTAssertTrue(store.unsaved.isEmpty)
    }

    func testStatusUsesGestationalWeeks() {
        let store = makeStore()
        store.gestationalWeeks = 34
        for _ in 0..<4 { contract(store, seconds: 40, then: 260) }
        now -= 260  // 停在第 4 次刚结束
        XCTAssertEqual(store.status?.stage, .pretermAlert)
        store.gestationalWeeks = 38
        XCTAssertNotEqual(store.status?.stage, .pretermAlert)
    }

    func testStaleTimerNeedsADecision() {
        let store = makeStore()
        contract(store, rest: 0)
        XCTAssertFalse(store.needsStaleDecision)
        now += 21_601
        XCTAssertTrue(store.needsStaleDecision)
        store.discardActive()
        XCTAssertFalse(store.needsStaleDecision)
        XCTAssertNil(store.active)
    }

    func testResumeAfterLaunchCapsALongRunningContraction() {
        let store = makeStore()
        store.toggle()
        now += 3600
        store.resumeAfterLaunch()
        XCTAssertEqual(store.active?.isContracting, false)
        XCTAssertEqual(store.active?.entries().first?.duration, 600)
    }

    func testRemoveLastPersists() {
        let store = makeStore()
        contract(store)
        store.removeLast()
        XCTAssertEqual(makeStore().active?.spans.isEmpty, true)
    }
}
```

`<<…>>` 处按 Step 1 开头找到或写好的假仓库填写，提交的测试文件里不得留下 `<<`。写完先 `grep -n "<<" apps/ios/AimApp/Tests/ContractionStoreTests.swift` 确认没有遗留。

- [ ] **Step 2: 登记工程文件，运行，确认失败**

登记 `Features/Labor/ContractionStore.swift`（181，App，`Labor` group）和 `Tests/ContractionStoreTests.swift`（188，测试）。
Run: 跑 `ContractionStoreTests`。Expected: 编译失败。

- [ ] **Step 3: 实现**

`apps/ios/AimApp/Features/Labor/ContractionStore.swift`。结构照 `FetalMovementStore`：作用域、落盘、队列逐条保存、按作用域丢弃过期响应。去掉它特有的计数页登记和过期收尾：宫缩计时没有「到点自动结束」。

```swift
import Foundation
import Observation

/// 宫缩计时的状态：进行中的计时（本地断点）、没保存上的结果、档案里的历史。
///
/// 计时可能持续好几个小时，中途被系统回收是常态，断点和未保存结果都写进 UserDefaults。
/// 本地数据按「账号 + 孕期」分开存，做法与 `FetalMovementStore` 相同；未绑定时所有操作都不生效。
@MainActor
@Observable
final class ContractionStore {
    var repository: BusinessRepositoryProtocol?
    var clock: () -> Date = { Date() }
    var gestationalWeeks: Int?
    private(set) var active: ContractionTimer?
    private(set) var unsaved: [ContractionResult] = []
    private(set) var sessions: [ContractionSession] = []
    private(set) var isSaving = false
    var errorMessage: String?

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var scope: Scope?
    private var reloadGeneration = 0
    private var appliedReloadGeneration = 0

    private struct Scope: Equatable {
        let accountID: UUID
        let pregnancyID: UUID

        private var prefix: String { "aim.contraction.\(accountID.uuidString).\(pregnancyID.uuidString)" }
        var activeKey: String { prefix + ".active" }
        var unsavedKey: String { prefix + ".unsaved" }
    }

    init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    func bind(accountID: UUID, pregnancyID: UUID) {
        let next = Scope(accountID: accountID, pregnancyID: pregnancyID)
        guard next != scope else { return }
        scope = next
        active = Self.read(ContractionTimer.self, key: next.activeKey, from: defaults)
        unsaved = Self.read([ContractionResult].self, key: next.unsavedKey, from: defaults) ?? []
        sessions = []
        errorMessage = nil
    }

    /// 解绑时连仓库一起清掉：它按值带着上一家的身份。
    func unbind() {
        scope = nil
        repository = nil
        active = nil
        unsaved = []
        sessions = []
        errorMessage = nil
    }

    var status: ContractionStatus? {
        active.map { ContractionMath.status($0, at: clock(), weeks: gestationalWeeks) }
    }

    var needsStaleDecision: Bool { active?.isStale(at: clock()) ?? false }
    var latest: ContractionSession? { sessions.first }

    func load() async {
        do { try await reloadSessions() } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func toggle() -> ContractionTimer.ToggleResult {
        guard let scope else { return .ignored }
        var timer = active ?? ContractionTimer()
        let result = timer.toggle(at: clock())
        active = timer.spans.isEmpty ? nil : timer
        persist(scope)
        return result
    }

    func removeLast() {
        guard let scope, var timer = active else { return }
        timer.removeLast()
        active = timer.spans.isEmpty ? nil : timer
        persist(scope)
    }

    func resumeAfterLaunch() {
        guard let scope, var timer = active else { return }
        timer.capRunning(at: clock())
        active = timer
        persist(scope)
    }

    func discardActive() {
        guard let scope else { return }
        active = nil
        persist(scope)
    }

    func finish() async -> (result: ContractionResult, savedRecordID: UUID?)? {
        guard let scope, let timer = active, let startedAt = timer.completed.first?.start else { return nil }
        let result = ContractionResult(id: UUID(), startedAt: startedAt, entries: timer.entries())
        // 先落盘再等待：防止等待期间被重复结束，也保证杀掉 App 不丢。
        active = nil
        unsaved.append(result)
        persist(scope)
        let savedID = await saveUnsaved(returning: result.id)
        return (result, savedID)
    }

    @discardableResult
    func saveUnsaved() async -> Bool {
        _ = await saveUnsaved(returning: nil)
        return unsaved.isEmpty
    }

    /// 按顺序保存队列；遇到失败就停。返回 `target` 那一条保存后的记录 id。
    private func saveUnsaved(returning target: UUID?) async -> UUID? {
        guard !isSaving, !unsaved.isEmpty else { return nil }
        guard let repository, let scope else {
            errorMessage = "没保存上，重试"
            return nil
        }
        isSaving = true
        var targetRecordID: UUID?
        while let result = unsaved.first, self.scope == scope {
            do {
                let record = try await repository.createRecord(draft: result.draft)
                if result.id == target { targetRecordID = record.id }
            } catch {
                if self.scope == scope { errorMessage = "没保存上，重试" }
                isSaving = false
                return nil
            }
            removeSaved(result, from: scope)
        }
        isSaving = false
        guard self.scope == scope else { return targetRecordID }
        errorMessage = nil
        notificationCenter.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["record"]])
        try? await reloadSessions()
        return targetRecordID
    }

    private func reloadSessions() async throws {
        guard let repository, let requestedScope = scope else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        let snapshot: RecordSnapshot
        do {
            snapshot = try await repository.fetchRecords(type: .contraction)
        } catch {
            guard scope == requestedScope, generation == reloadGeneration else { return }
            throw error
        }
        guard scope == requestedScope, generation > appliedReloadGeneration else { return }
        appliedReloadGeneration = generation
        sessions = snapshot.records
            .compactMap(ContractionSession.init(record:))
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func removeSaved(_ result: ContractionResult, from savedScope: Scope) {
        if scope == savedScope {
            unsaved.removeAll { $0.id == result.id }
            persist(savedScope)
        } else {
            var queue = Self.read([ContractionResult].self, key: savedScope.unsavedKey, from: defaults) ?? []
            queue.removeAll { $0.id == result.id }
            Self.write(queue.isEmpty ? nil : queue, key: savedScope.unsavedKey, to: defaults)
        }
    }

    private func persist(_ scope: Scope) {
        Self.write(active, key: scope.activeKey, to: defaults)
        Self.write(unsaved.isEmpty ? nil : unsaved, key: scope.unsavedKey, to: defaults)
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func write<T: Encodable>(_ value: T?, key: String, to defaults: UserDefaults) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
```

- [ ] **Step 4: 运行测试**

Run: 跑 `ContractionStoreTests`，再跑全部单元测试。Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add apps/ios/AimApp apps/ios/AimApp.xcodeproj/project.pbxproj
git commit -m "feat(ios): 宫缩计时的本地断点、保存与重试"
```

---

### Task 7: 去医院记录与首页横幅逻辑（纯数据）

**Files:**
- Create: `apps/ios/AimApp/Features/Labor/HospitalTrip.swift`（编号 185）
- Test: `apps/ios/AimApp/Tests/HospitalTripTests.swift`（编号 189）
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes：Task 4 的 `HospitalTripReason`、`HospitalTripRecordData`、`RecordItem`。
- Produces：

```swift
enum HospitalTrip {
    static let title = "我们出发去医院了"
    static let bannerWindow: TimeInterval = 86_400
    static func draft(reason: HospitalTripReason, note: String, contractionRecordID: UUID?, at now: Date) -> RecordDraft
    /// 首页要显示的那一条：24 小时内最新的一条；别人发的、本机已点「知道了」的不算。
    static func banner(in records: [RecordItem], now: Date, me: UUID?, dismissed: Set<UUID>) -> RecordItem?
    /// 「妈妈 10:32 出发去医院了 · 规律宫缩」
    static func bannerText(_ record: RecordItem, actorName: String) -> String
}

/// 本机已点「知道了」的去医院记录。
struct HospitalTripDismissals {
    init(defaults: UserDefaults = .standard)
    var ids: Set<UUID> { get }
    func dismiss(_ id: UUID)
}
```

- [ ] **Step 1: 写测试（先失败）**

`apps/ios/AimApp/Tests/HospitalTripTests.swift`：

```swift
import XCTest
@testable import AimApp

final class HospitalTripTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let me = UUID(), partner = UUID()

    private func trip(author: UUID, hoursAgo: Double, reason: HospitalTripReason = .contractions,
                      note: String? = nil) -> RecordItem {
        let at = now.addingTimeInterval(-hoursAgo * 3600)
        return RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: author,
            type: .hospitalTrip, occurredAt: at, visibility: .family, title: HospitalTrip.title,
            content: note, structuredData: .hospitalTrip(HospitalTripRecordData(reason: reason)),
            attachmentRefs: [], createdAt: at, updatedAt: at)
    }

    func testDraftIsAlwaysFamilyVisibleWithTrimmedNote() {
        let linked = UUID()
        let draft = HospitalTrip.draft(reason: .waterBroke, note: "  打车去市妇保 \n", contractionRecordID: linked, at: now)
        XCTAssertEqual(draft.type, .hospitalTrip)
        XCTAssertEqual(draft.visibility, .family)
        XCTAssertEqual(draft.title, "我们出发去医院了")
        XCTAssertEqual(draft.content, "打车去市妇保")
        XCTAssertEqual(draft.structuredData, .hospitalTrip(HospitalTripRecordData(reason: .waterBroke, contractionRecordID: linked)))
        XCTAssertNil(HospitalTrip.draft(reason: .other, note: "   ", contractionRecordID: nil, at: now).content)
    }

    func testBannerPicksTheLatestWithin24Hours() {
        let old = trip(author: partner, hoursAgo: 25)
        let recent = trip(author: partner, hoursAgo: 2)
        let newest = trip(author: partner, hoursAgo: 1)
        XCTAssertEqual(HospitalTrip.banner(in: [old, recent, newest], now: now, me: me, dismissed: [])?.id, newest.id)
        XCTAssertNil(HospitalTrip.banner(in: [old], now: now, me: me, dismissed: []))
    }

    func testOthersCanDismissButTheAuthorAlwaysSeesTheirOwn() {
        let mine = trip(author: me, hoursAgo: 1)
        let theirs = trip(author: partner, hoursAgo: 1)
        XCTAssertNil(HospitalTrip.banner(in: [theirs], now: now, me: me, dismissed: [theirs.id]))
        XCTAssertEqual(HospitalTrip.banner(in: [mine], now: now, me: me, dismissed: [mine.id])?.id, mine.id,
                       "作者看到的是「撤回」，不会被「知道了」藏掉")
    }

    func testBannerText() {
        let record = trip(author: partner, hoursAgo: 1, reason: .waterBroke)
        let time = record.occurredAt.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(HospitalTrip.bannerText(record, actorName: "妈妈"), "妈妈 \(time) 出发去医院了 · 破水")
        let withNote = trip(author: partner, hoursAgo: 1, note: "爸爸陪着")
        XCTAssertTrue(HospitalTrip.bannerText(withNote, actorName: "妈妈").hasSuffix("· 爸爸陪着"))
    }

    func testDismissalsPersist() {
        let defaults = UserDefaults(suiteName: "HospitalTripTests.\(UUID().uuidString)")!
        let id = UUID()
        HospitalTripDismissals(defaults: defaults).dismiss(id)
        XCTAssertEqual(HospitalTripDismissals(defaults: defaults).ids, [id])
    }
}
```

`HospitalTripRecordData(reason:)` 依赖 `contractionRecordID` 有缺省值 nil（Task 4 声明为 `var contractionRecordID: UUID?`，逐成员初始化器会带缺省值）。

- [ ] **Step 2: 登记工程文件，运行，确认失败**

登记 185（App，`Labor` group）、189（测试）。Run: 跑 `HospitalTripTests`。Expected: 编译失败。

- [ ] **Step 3: 实现**

`apps/ios/AimApp/Features/Labor/HospitalTrip.swift`：

```swift
import Foundation

/// 「我们出发去医院了」：一条全家可见的记录。没有推送，家人打开 App 时在首页看到横幅。
enum HospitalTrip {
    static let title = "我们出发去医院了"
    static let bannerWindow: TimeInterval = 86_400

    static func draft(reason: HospitalTripReason, note: String, contractionRecordID: UUID?, at now: Date) -> RecordDraft {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return RecordDraft(
            type: .hospitalTrip, occurredAt: now, visibility: .family, title: title,
            content: trimmed.isEmpty ? nil : String(trimmed.prefix(200)),
            structuredData: .hospitalTrip(HospitalTripRecordData(reason: reason, contractionRecordID: contractionRecordID)))
    }

    static func banner(in records: [RecordItem], now: Date, me: UUID?, dismissed: Set<UUID>) -> RecordItem? {
        records
            .filter { record in
                guard record.type == .hospitalTrip else { return false }
                let age = now.timeIntervalSince(record.occurredAt)
                guard age >= -300, age <= bannerWindow else { return false }
                return record.authorAccountID == me || !dismissed.contains(record.id)
            }
            .max { $0.occurredAt < $1.occurredAt }
    }

    static func bannerText(_ record: RecordItem, actorName: String) -> String {
        let time = record.occurredAt.formatted(date: .omitted, time: .shortened)
        let detail: String = {
            if let note = record.content?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { return note }
            if case let .hospitalTrip(data) = record.structuredData { return data.reason.displayName }
            return ""
        }()
        let base = "\(actorName) \(time) 出发去医院了"
        return detail.isEmpty ? base : "\(base) · \(detail)"
    }
}

struct HospitalTripDismissals {
    private static let key = "aim.hospitalTrip.dismissed"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var ids: Set<UUID> {
        Set((defaults.stringArray(forKey: Self.key) ?? []).compactMap(UUID.init(uuidString:)))
    }

    func dismiss(_ id: UUID) {
        defaults.set((ids.union([id])).map(\.uuidString), forKey: Self.key)
    }
}
```

`age >= -300` 容忍手机之间的时钟差：别人手机快几分钟，记录时间会落在「未来」。

- [ ] **Step 4: 运行测试**

Run: 跑 `HospitalTripTests`，再跑全部单元测试。Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add apps/ios/AimApp apps/ios/AimApp.xcodeproj/project.pbxproj
git commit -m "feat(ios): 去医院记录草稿与首页横幅筛选"
```

---

### Task 8: 计时页、分娩页与「我们出发去医院了」确认页

**Files:**
- Create: `apps/ios/AimApp/Features/Labor/LaborCopy.swift`（编号 182）
- Create: `apps/ios/AimApp/Features/Labor/ContractionTimerView.swift`（编号 183）
- Create: `apps/ios/AimApp/Features/Labor/LaborView.swift`（编号 184）
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`、`apps/ios/AimApp/App/AimApp.swift`

**Interfaces:**
- Consumes：
  - Task 6 的 `ContractionStore`，通过 `@Environment(ContractionStore.self)` 注入。
  - Task 7 的 `HospitalTrip.draft`。
  - 已有的 `LibraryStore`、`AgentStore`、`LibraryCategoryDetail(category:store:agentStore:)`、`EncyclopediaEntryView`、`AgentView`。
  - `AgentContext`：先看 `FetalMovementView` 的「问 AIM」是怎么构造上下文、怎么打开 AIM 的，照抄。
- Produces（Task 9 使用）：
  - `struct LaborView: View { init(libraryStore: LibraryStore, agentStore: AgentStore) }`。
  - `struct ContractionTimerView: View { init(agentStore: AgentStore, onClose: @escaping () -> Void) }`。
  - `struct HospitalTripSheet: View { init(defaultReason: HospitalTripReason, contractionRecordID: UUID?, onDone: @escaping (Bool) -> Void) }`，参数为是否已保存。
  - 无障碍标识（UI 测试用）：
    - 分娩页：`labor-page`、`labor-start-timer`、`labor-hospital-trip`、`labor-call-120`、`labor-preparation`。
    - 计时页：`contraction-toggle`、`contraction-finish`、`contraction-remove-last`、`contraction-status`、`contraction-hospital-trip`、`contraction-close`。
    - 确认页：`hospital-trip-confirm`、`hospital-trip-note`。

- [ ] **Step 1: 文案常量**

`apps/ios/AimApp/Features/Labor/LaborCopy.swift`：

```swift
import Foundation

/// 分娩模式的医学文案。集中在这里便于产科医生复核（见 content/README.md「待产科医生复核」）。
/// 原则：不说「正常」，不说「还不用去」；5-1-1 只是参考，以医生交代为准。
enum LaborCopy {
    static let pretermBanner = "还没满 37 周。出现规律宫缩可能是早产，不用等到 5-1-1，请现在联系医院。"

    static let goNowTitle = "这些情况不用等宫缩规律，立即去医院"
    static let goNowItems = [
        "破水（不管有没有宫缩）",
        "阴道流血像月经那么多或更多",
        "持续剧烈腹痛，不缓解",
        "胎动明显减少或停止",
        "头痛、眼花、抽搐",
        "不足 37 周出现规律宫缩",
    ]

    static let whenToLeaveTitle = "什么时候出发"
    static let whenToLeave = [
        "第一次生的常用参考「5-1-1」：约 5 分钟一次、每次约 1 分钟、持续 1 小时。",
        "生过孩子的产程可能更快，宫缩规律（约 10 分钟一次）就联系医院。",
        "医生交代过别的时机，以医生为准。",
    ]
    static let doctorFirst = "医生交代过别的时机，以医生为准"

    static func stageTitle(_ stage: ContractionStage) -> String {
        switch stage {
        case .early: "还不规律，继续记录"
        case .approaching: "越来越规律了"
        case .go: "符合 5-1-1，现在出发去医院"
        case .pretermAlert: "未满 37 周宫缩频繁，现在联系医院"
        }
    }

    static func stageDetail(_ stage: ContractionStage) -> String {
        switch stage {
        case .early: "可以休息、吃点东西、喝水，继续按开始和结束。出现下面的情况不用等，立即去医院。"
        case .approaching: "收好待产包、安排好车、告诉家人。生过孩子的，现在就联系医院。"
        case .go: "按医生交代的去医院。路上继续计时也可以。"
        case .pretermAlert: "可能是早产。请现在联系你的产检医院或去产科急诊，必要时拨打 120。"
        }
    }

    static func quiet(minutes: Int) -> String { "已经 \(minutes) 分钟没有宫缩了" }
    static let longRunning = "这次宫缩已经超过 3 分钟。如果是持续剧痛不缓解，请立即去医院。忘了按结束就现在按。"

    static let tripExplanation = "家人下次打开 App 会在首页看到。现在还不能推送到他们的手机，急事请直接打电话。"
    static let tripSaved = "已告诉家人。路上注意安全"
    static let staleTitle = "上次计时还没保存"
    static let staleMessage = "最后一次宫缩已经过去 6 个多小时。先保存或丢弃，再开始新的计时。"
}
```

- [ ] **Step 2: 计时页**

`apps/ios/AimApp/Features/Labor/ContractionTimerView.swift`。全屏，每秒刷新用 `SwiftUI.TimelineView(.periodic(from: .now, by: 1))`。结构：

```swift
import SwiftUI
import UIKit

/// 宫缩计时（全屏）：按开始、按结束，实时显示 5-1-1 档位。规格 6.2。
struct ContractionTimerView: View {
    @Environment(ContractionStore.self) private var store
    let agentStore: AgentStore
    let onClose: () -> Void

    @State private var confirmingFinish = false
    @State private var trip: TripLaunch?
    @State private var lastAlertedStage: ContractionStage?

    private struct TripLaunch: Identifiable {
        let id = UUID()
        let contractionRecordID: UUID?
    }

    var body: some View {
        NavigationStack {
            SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { _ in
                ScrollView {
                    VStack(spacing: AimMetrics.space16) {
                        if let weeks = store.gestationalWeeks, weeks < ContractionMath.pretermWeeks {
                            notice(LaborCopy.pretermBanner, color: .aimDanger)
                        }
                        statusCard
                        if store.status?.isLongRunning == true {
                            notice(LaborCopy.longRunning, color: .aimDanger)
                        }
                        toggleButton
                        goNowCard
                        historyList
                    }
                    .padding(AimMetrics.space16)
                }
            }
            .background(Color.aimCanvas)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 关掉页面不结束计时：断点在本地，回来接着记。
                    Button("收起", action: onClose).accessibilityIdentifier("contraction-close")
                }
            }
            .navigationTitle("宫缩计时")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { store.resumeAfterLaunch() }
        .onChange(of: store.status?.stage) { _, stage in
            guard let stage, stage == .go || stage == .pretermAlert, stage != lastAlertedStage else { return }
            lastAlertedStage = stage
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        .confirmationDialog("结束这次计时？", isPresented: $confirmingFinish, titleVisibility: .visible) {
            Button("结束并保存") { Task { await finish(thenTrip: false) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("正在进行的这次宫缩不计入。")
        }
        .alert(LaborCopy.staleTitle, isPresented: .constant(store.needsStaleDecision)) {
            Button("保存") { Task { await finish(thenTrip: false) } }
            Button("丢弃", role: .destructive) { store.discardActive() }
        } message: {
            Text(LaborCopy.staleMessage)
        }
        .sheet(item: $trip) { launch in
            HospitalTripSheet(defaultReason: .contractions, contractionRecordID: launch.contractionRecordID) { saved in
                trip = nil
                if saved { onClose() }
            }
        }
    }
}
```

视图其余部分写成 `private var` / `private func`，要求如下：

- `statusCard`（`accessibilityIdentifier("contraction-status")`）：
  - 标题 `LaborCopy.stageTitle(stage)`。有 `quietMinutes` 时标题下面加一行 `LaborCopy.quiet(minutes:)`。
  - 下面一行：「最近 1 小时 N 次 · 平均 X 一次 · 每次约 Y」，用 `ContractionFormat.seconds`，`summary` 为 nil 时显示「按下面的按钮开始记录第一次宫缩」。
  - 再下面一行小字 `LaborCopy.doctorFirst`。
  - 颜色：`early` 用 `Color.aimSurface`，`approaching` 用提醒色，`go` 用强调色，`pretermAlert` 用危险色。先 `grep -n "static let aim" apps/ios/AimApp/Core/**/*.swift` 查实际有哪些颜色名，用最接近的。
  - `stage` 为 `.go` 或 `.pretermAlert` 时，卡内展开两个按钮：「我们出发去医院了」（`contraction-hospital-trip`，调 `finish(thenTrip: true)`）和「打 120」（`Link(destination: URL(string: "tel://120")!)`）。
- `toggleButton`（`contraction-toggle`）：
  - 直径约 200 的圆形按钮。没在宫缩时文字为「宫缩开始」；宫缩中为「宫缩结束」，下面显示 `runningSeconds` 的 mm:ss。
  - 点击调 `store.toggle()`，返回 `.began` 或 `.ended` 时 `UIImpactFeedbackGenerator(style: .medium).impactOccurred()`。
- `goNowCard`：
  - `LaborCopy.goNowTitle` 加 `goNowItems` 列表，右上角「打 120」。
  - 常驻显示，不折叠（规格风险一节）。
- `historyList`：
  - 倒序列出 `store.active?.spans`：开始时刻（`formatted(date: .omitted, time: .standard)`）、持续（进行中显示「进行中」）、与上一次开始的间隔。
  - 列表上方有「删掉上一次」按钮（`contraction-remove-last`），点击调 `store.removeLast()`，没有记录时禁用。
- `bottomBar`：
  - 「结束计时」（`contraction-finish`）：`store.active?.completed.isEmpty != false` 时禁用，点击弹 `confirmingFinish`。
  - 「我们出发去医院了」（`contraction-hospital-trip`）：直接调 `finish(thenTrip: true)`；没有已结束的宫缩时直接 `trip = TripLaunch(contractionRecordID: nil)`。
  - 计时页只能有一个 `contraction-hospital-trip`：状态卡展开时，底部这个按钮隐藏。
  - `store.errorMessage` 不为 nil 时上方显示一行红字和「重试」按钮，调 `store.saveUnsaved()`。
- `finish(thenTrip:)`：

```swift
    private func finish(thenTrip: Bool) async {
        let outcome = await store.finish()
        if thenTrip {
            trip = TripLaunch(contractionRecordID: outcome?.savedRecordID)
        } else if outcome?.savedRecordID != nil {
            onClose()
        }
        // 没保存上：留在页面，errorMessage 会显示「没保存上，重试」。
    }
```

- [ ] **Step 3: 分娩页与确认页**

`apps/ios/AimApp/Features/Labor/LaborView.swift`：

```swift
import SwiftUI

/// 分娩页：宫缩计时、立即就医的情况、什么时候出发、待产包、「我们出发去医院了」。规格 6.1。
struct LaborView: View {
    @Environment(ContractionStore.self) private var contractions
    let libraryStore: LibraryStore
    let agentStore: AgentStore

    @State private var timing = false
    @State private var showingTrip = false
    @State private var showingWhenToGo = false
    @State private var toast: AimToastMessage?

    var body: some View {
        ScrollView {
            VStack(spacing: AimMetrics.space12) {
                if let weeks = contractions.gestationalWeeks, weeks < ContractionMath.pretermWeeks {
                    pretermNotice
                }
                timerCard
                goNowCard
                whenToLeaveCard
                preparationCard
                tripButton
            }
            .padding(.horizontal, AimMetrics.space16)
            .padding(.bottom, AimMetrics.space28)
        }
        .background(Color.aimCanvas)
        .accessibilityIdentifier("labor-page")
        .navigationTitle("分娩准备")
        .task { await contractions.load() }
        .fullScreenCover(isPresented: $timing) {
            ContractionTimerView(agentStore: agentStore) { timing = false }
        }
        .sheet(isPresented: $showingTrip) {
            HospitalTripSheet(defaultReason: .contractions, contractionRecordID: nil) { saved in
                showingTrip = false
                if saved {
                    toast = AimToastMessage(text: LaborCopy.tripSaved, undoTitle: "",
                                            accessibilityIdentifier: "labor-trip-saved")
                }
            }
        }
        .aimToast($toast)
    }
}
```

其余部分写成 `private var`，要求如下：

- `timerCard`（`labor-start-timer` 放在按钮上）：
  - `contractions.active == nil` 时，按钮「开始宫缩计时」，下面一行 `contractions.latest.map { "上次 " + ContractionFormat.summary($0.data) }`。
  - 有进行中的计时时，显示 `LaborCopy.stageTitle(status.stage)` 和「第 N 次」，按钮改为「回到计时」。
  - 两种状态都是点击后 `timing = true`。
- `goNowCard`：同计时页，「打 120」按钮标识 `labor-call-120`。
- `whenToLeaveCard`：
  - `LaborCopy.whenToLeaveTitle` 加 `whenToLeave` 三句。
  - 「详细说明」打开百科 `birth.when-to-go`：先看 `EncyclopediaEntryView` 的初始化参数，以及其他地方怎么按条目编号从 `libraryStore` 取条目（`grep -rn "EncyclopediaEntryView(" apps/ios/AimApp/Features`），照抄。取不到条目时隐藏这个链接。
- `preparationCard`（`labor-preparation`）：
  - `NavigationLink` 到 `LibraryCategoryDetail(category: .preparation, store: libraryStore, agentStore: agentStore)`。
  - 标题「待产包」，副标题用资料库待产包分类的摘要：`LibraryCategory.preparation.summary(from: libraryStore.snapshot).headline`，先 `grep -n "func summary\|var snapshot" apps/ios/AimApp/Features/Library/LibraryCatalog.swift apps/ios/AimApp/Features/Library/LibraryStore.swift` 确认实际名字。
- `tripButton`（`labor-hospital-trip`）：大号 `.borderedProminent` 按钮「我们出发去医院了」，点击 `showingTrip = true`。
- 右上角工具栏「问 AIM」：照 `FetalMovementView` 的写法打开 AIM，上下文两行：「当前在分娩准备页」，以及 `contractions.latest` 的摘要（有的话）。

同文件加确认页：

```swift
/// 「我们出发去医院了」：选原因、写一句备注，保存为全家可见的记录。规格 6.3。
struct HospitalTripSheet: View {
    @Environment(\.businessRepository) private var repository
    let defaultReason: HospitalTripReason
    let contractionRecordID: UUID?
    let onDone: (Bool) -> Void

    @State private var reason: HospitalTripReason
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?

    init(defaultReason: HospitalTripReason, contractionRecordID: UUID?, onDone: @escaping (Bool) -> Void) {
        self.defaultReason = defaultReason
        self.contractionRecordID = contractionRecordID
        self.onDone = onDone
        _reason = State(initialValue: defaultReason)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("为什么去") {
                    Picker("原因", selection: $reason) {
                        ForEach(HospitalTripReason.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    TextField("一句话备注（可不填）", text: $note, axis: .vertical)
                        .accessibilityIdentifier("hospital-trip-note")
                } footer: {
                    Text(LaborCopy.tripExplanation)
                }
                if let error { Section { Text(error).foregroundStyle(Color.aimDanger) } }
            }
            .navigationTitle("我们出发去医院了")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { onDone(false) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("告诉家人") { Task { await save() } }
                        .disabled(saving)
                        .accessibilityIdentifier("hospital-trip-confirm")
                }
            }
        }
    }

    private func save() async {
        guard let repository else { error = "没保存上，重试"; return }
        saving = true
        defer { saving = false }
        do {
            _ = try await repository.createRecord(draft: HospitalTrip.draft(
                reason: reason, note: note, contractionRecordID: contractionRecordID, at: .now))
            NotificationCenter.default.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["record"]])
            onDone(true)
        } catch {
            self.error = "没保存上，重试"
        }
    }
}
```

`\.businessRepository` 这个环境值若不存在（先 `grep -rn "businessRepository" apps/ios/AimApp | head`），改为让 `HospitalTripSheet` 在初始化参数里接收 `repository: BusinessRepositoryProtocol?`，调用方从 `ContractionStore.repository` 传入。`ContractionStore.repository` 已由 App 设置，是同一个仓库实例。Produces 里的初始化签名相应加上这个参数，并在 Task 9 的调用处一并传入。

- [ ] **Step 4: 注入 Store**

`App/AimApp.swift`：
1. 声明：`@State private var contractionStore = ContractionStore()`，放在 `fetalMovementStore` 声明之后。
2. `.environment(fetalMovementStore)` 之后加 `.environment(contractionStore)`。
3. `reloadRepositories()` 里，照 `fetalMovementStore` 的绑定方式绑定：
   - `contractionStore.repository = repository`；
   - 有账号和孕期时 `bind`，否则 `unbind`；
   - 在胎动 `load()` 之后：`contractionStore.gestationalWeeks = homeStore.pregnancy?.weeks; contractionStore.resumeAfterLaunch(); await contractionStore.saveUnsaved(); await contractionStore.load()`（仅在已绑定时）。
4. `.onReceive(... .aimDataChanged ...)` 不用改，宫缩自己保存后会刷新。

- [ ] **Step 5: 登记工程文件，构建**

登记 182、183、184（App，`Labor` group）。
Run: `cd apps/ios && xcodebuild build -project AimApp.xcodeproj -scheme AimApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro' 2>&1 | grep -E "error|BUILD" | head -20`
Expected: `BUILD SUCCEEDED`。再跑全部单元测试，确认全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add apps/ios/AimApp apps/ios/AimApp.xcodeproj/project.pbxproj
git commit -m "feat(ios): 宫缩计时页、分娩页与「我们出发去医院了」"
```

---

### Task 9: 首页置顶卡、分娩准备卡与各入口

**Files:**
- Create: `apps/ios/AimApp/Features/Labor/LaborHomeCards.swift`（编号 186）
- Modify: `apps/ios/AimApp/Features/Home/HomeDashboardStore.swift`、`HomeDashboardView.swift`
- Modify: `apps/ios/AimApp/Features/Library/LibraryCategoryDetail.swift:29`、`EncyclopediaEntryView.swift:114`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`
- Test: 在已有的 `HomeDashboardStore` 测试文件里加用例（`grep -ln "HomeDashboardStore" apps/ios/AimApp/Tests/`）；没有这个文件就加进 `Tests/HospitalTripTests.swift`

**Interfaces:**
- Consumes：
  - Task 6 的 `ContractionStore`；Task 7 的 `HospitalTrip`、`HospitalTripDismissals`；Task 8 的 `LaborView`、`ContractionTimerView`。
  - `HomeDashboardStore.members: [FamilyMember]`（`displayName`）、`pregnancy?.weeks`。
- Produces：
  - `HomeDashboardStore.hospitalTrips: [RecordItem]`。
  - 首页卡片：`LaborBannerCard`、`ContractionActiveCard`、`LaborPrepCard`。
  - 无障碍标识：`home-hospital-trip-banner`、`home-hospital-trip-withdraw`、`home-hospital-trip-dismiss`、`home-contraction-active`、`home-labor-card`、`library-labor-entry`、`encyclopedia-start-contraction`。

- [ ] **Step 1: 写测试（先失败）**

```swift
    func testHomeStoreLoadsHospitalTrips() async {
        // 用该测试文件已有的假仓库；让 fetchRecords(type: .hospitalTrip) 返回一条去医院记录。
        let store = HomeDashboardStore()
        store.repository = <<返回一条 hospitalTrip 记录的假仓库>>
        await store.load()
        XCTAssertEqual(store.hospitalTrips.count, 1)
        XCTAssertEqual(store.hospitalTrips.first?.type, .hospitalTrip)
    }
```

照该测试文件已有的假仓库写法填入，提交时不得留下 `<<`。若那个假仓库的 `fetchRecords` 不区分类型，就让它对 `.hospitalTrip` 返回这条记录、对其他类型返回空。

- [ ] **Step 2: 运行，确认失败**

Expected: 编译失败，`hospitalTrips` 未定义。

- [ ] **Step 3: 实现首页数据**

`HomeDashboardStore`：
- 加 `var hospitalTrips: [RecordItem] = []`。
- `load()` 里并行加一项 `async let tripsResult = Self.capture { try await repository.fetchRecords(type: .hospitalTrip) }`。
- 成功时 `hospitalTrips = snapshot.records`，失败时保持原值、不报错。去医院横幅拿不到不该影响别的块。
- 加 `func withdraw(_ record: RecordItem) async -> Bool`：调 `repository.deleteRecord(recordID:)`，成功后从 `hospitalTrips` 移除，并广播 `.aimDataChanged`（`kinds: ["record"]`）。

- [ ] **Step 4: 首页卡片**

`apps/ios/AimApp/Features/Labor/LaborHomeCards.swift`：

```swift
import SwiftUI

/// 首页置顶的去医院横幅：24 小时内家里有人出发去医院了。规格 6.4。
struct LaborBannerCard: View {
    let record: RecordItem
    let actorName: String
    let isMine: Bool
    let onOpen: () -> Void
    let onWithdraw: () -> Void
    let onDismiss: () -> Void
    @State private var confirmingWithdraw = false

    var body: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Button(action: onOpen) {
                HStack(alignment: .top) {
                    Image(systemName: "car.fill")
                    Text(HospitalTrip.bannerText(record, actorName: actorName))
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-hospital-trip-banner")
            HStack {
                Spacer()
                if isMine {
                    Button("说错了，撤回") { confirmingWithdraw = true }
                        .accessibilityIdentifier("home-hospital-trip-withdraw")
                } else {
                    Button("知道了", action: onDismiss)
                        .accessibilityIdentifier("home-hospital-trip-dismiss")
                }
            }
            .font(.subheadline)
        }
        .foregroundStyle(.white)
        .padding(AimMetrics.space16)
        .background(Color.aimAccent, in: RoundedRectangle(cornerRadius: AimMetrics.radius16))
        .confirmationDialog("撤回这条？", isPresented: $confirmingWithdraw, titleVisibility: .visible) {
            Button("撤回", role: .destructive, action: onWithdraw)
            Button("取消", role: .cancel) {}
        } message: {
            Text("家人那边的横幅和动态也会一起消失。")
        }
    }
}

/// 本机有进行中的宫缩计时：首页置顶显示，点进计时页。
struct ContractionActiveCard: View {
    @Environment(ContractionStore.self) private var store
    let onOpen: () -> Void

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { _ in
            Button(action: onOpen) {
                HStack {
                    VStack(alignment: .leading, spacing: AimMetrics.space4) {
                        Text("宫缩计时中").font(.headline).foregroundStyle(Color.aimTextPrimary)
                        Text(subtitle).font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.aimTextTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .aimCard()
            .accessibilityIdentifier("home-contraction-active")
        }
    }

    private var subtitle: String {
        guard let status = store.status else { return "" }
        var parts = [LaborCopy.stageTitle(status.stage)]
        if let summary = status.summary {
            parts.append("\(summary.count) 次")
            if let interval = summary.avgIntervalSeconds { parts.append("约 \(ContractionFormat.seconds(interval))一次") }
        }
        return parts.joined(separator: " · ")
    }
}

/// 孕 36 周起：「分娩准备」入口。
struct LaborPrepCard: View {
    let libraryStore: LibraryStore
    let agentStore: AgentStore

    var body: some View {
        NavigationLink {
            LaborView(libraryStore: libraryStore, agentStore: agentStore)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: AimMetrics.space4) {
                    Text("分娩准备").font(.headline).foregroundStyle(Color.aimTextPrimary)
                    Text("宫缩计时、什么时候去医院、待产包").font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.aimTextTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aimCard()
        .accessibilityIdentifier("home-labor-card")
    }
}
```

`Color.aimAccent`、`AimMetrics.radius16`、`aimCard()` 的实际名字先 grep 确认（`grep -rn "static let aim\|static let radius" apps/ios/AimApp/Core | head -30`），用实际存在的。

- [ ] **Step 5: 接进首页与入口**

`HomeDashboardView`：
1. 加 `@Environment(ContractionStore.self) private var contractions`、`@State private var timingContractions = false`、`@State private var openedTrip: RecordItem?`、`@State private var dismissedTrips = HospitalTripDismissals().ids`。
2. `VStack` 里 `header` 之后、`heroCard` 之前加 `pinnedLaborCard`：

```swift
    @ViewBuilder
    private var pinnedLaborCard: some View {
        if let trip = HospitalTrip.banner(in: store.hospitalTrips, now: .now, me: session.accountID, dismissed: dismissedTrips) {
            LaborBannerCard(
                record: trip,
                actorName: store.members.first { $0.accountID == trip.authorAccountID }?.displayName ?? "家人",
                isMine: trip.authorAccountID == session.accountID,
                onOpen: { openedTrip = trip },
                onWithdraw: { Task { _ = await store.withdraw(trip) } },
                onDismiss: {
                    HospitalTripDismissals().dismiss(trip.id)
                    dismissedTrips.insert(trip.id)
                })
        } else if contractions.active != nil {
            ContractionActiveCard { timingContractions = true }
        }
    }
```

3. 胎动卡之后加：

```swift
                    // 分娩准备从孕 36 周开始出现在首页；更早也能从资料库进入。
                    if (store.pregnancy?.weeks ?? 0) >= 36 {
                        LaborPrepCard(libraryStore: libraryStore, agentStore: agentStore)
                    }
```

4. 加两个呈现：
   - `.fullScreenCover(isPresented: $timingContractions) { ContractionTimerView(agentStore: agentStore) { timingContractions = false } }`；
   - `.sheet(item: $openedTrip) { record in NavigationStack { RecordDetailView(...) } }`。`RecordDetailView` 的初始化参数照 `RecordsView` 里打开详情的写法。
5. 首页 `load()` 完成后同步孕周：在 `.task { await store.load() }` 和 `.refreshable` 里，`load()` 之后加 `contractions.gestationalWeeks = store.pregnancy?.weeks`。

`LibraryCategoryDetail.swift`：在 `case .preparation: checklist(collection: "preparation")` 所在的 `switch` 外层，`.preparation` 分类内容顶部加一行入口：

```swift
NavigationLink {
    LaborView(libraryStore: store, agentStore: agentStore)
} label: {
    Label("宫缩计时与去医院", systemImage: "waveform.path.ecg")
}
.accessibilityIdentifier("library-labor-entry")
```

放置方式照该文件里其他分类顶部入口的写法（如有）；没有就放在 `checklist(collection:)` 列表之前，同一个容器里。

`EncyclopediaEntryView.swift:114`：在 `body.fetal-movement` 特例之后加：

```swift
                if entry.id == "birth.signs-of-labor" || entry.id == "birth.when-to-go" {
                    Button { timingContractions = true } label: {
                        Label("开始宫缩计时", systemImage: "waveform.path.ecg")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("encyclopedia-start-contraction")
                }
```

并照 `countingFetalMovement` 的写法加 `@State private var timingContractions = false` 和对应的 `.fullScreenCover`，展示 `ContractionTimerView(agentStore: agentStore) { timingContractions = false }`。若该视图没有 `agentStore`，照 `countingFetalMovement` 那个 cover 拿 `agentStore` 的方式拿。

- [ ] **Step 6: 登记、运行测试**

登记 186（App，`Labor` group）。
Run: 构建并跑全部单元测试。Expected: `BUILD SUCCEEDED`，全部 PASS。

- [ ] **Step 7: 提交**

```bash
git add apps/ios/AimApp apps/ios/AimApp.xcodeproj/project.pbxproj
git commit -m "feat(ios): 首页去医院横幅、计时中置顶卡与分娩准备入口"
```

---

### Task 10: UI 用例与路线图收尾

**Files:**
- Modify: `apps/ios/AimApp/UITests/CoreJourneyUITests.swift`（胎动用例 `testCountingFetalMovementFromHome` 之后）
- Modify: `docs/superpowers/2026-10-roadmap.md`

**Interfaces:**
- Consumes：Task 8、9 的无障碍标识；已有的 `registerNewAccount(in:)`、`completePregnancySetup(in:daysUntilDue:)`、`reveal(_:in:)`。

- [ ] **Step 1: 写 UI 用例**

```swift
    /// 孕 36 周起首页有「分娩准备」：计时两次宫缩并保存，然后告诉家人出发去医院，首页出现横幅，撤回后消失。
    func testLaborModeTimesContractionsAndAnnouncesTheHospitalTrip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        registerNewAccount(in: app)
        // 距预产期 20 天 ≈ 孕 37 周。
        completePregnancySetup(in: app, daysUntilDue: 20)

        let laborCard = app.buttons["home-labor-card"]
        reveal(laborCard, in: app)
        laborCard.tap()
        XCTAssertTrue(app.descendants(matching: .any)["labor-page"].waitForExistence(timeout: 10))

        app.buttons["labor-start-timer"].tap()
        let toggle = app.buttons["contraction-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        for _ in 0..<2 {
            toggle.tap()          // 开始
            sleep(2)
            toggle.tap()          // 结束
            sleep(2)
        }
        app.buttons["contraction-finish"].tap()
        app.buttons["结束并保存"].tap()

        // 保存成功后计时页关闭，回到分娩页；分娩页显示上一次的摘要。
        let lastSummary = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '上次 2 次'")).firstMatch
        XCTAssertTrue(lastSummary.waitForExistence(timeout: 15), "分娩页应当显示刚保存的那次计时")

        app.buttons["labor-hospital-trip"].tap()
        let confirm = app.buttons["hospital-trip-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()

        // 回首页看横幅。
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let banner = app.buttons["home-hospital-trip-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "首页应当出现去医院横幅")

        app.buttons["home-hospital-trip-withdraw"].tap()
        app.buttons["撤回"].tap()
        let gone = NSPredicate(format: "exists == false")
        wait(for: [expectation(for: gone, evaluatedWith: banner, handler: nil)], timeout: 15)
    }
```

`daysUntilDue: 20` ≈ 280 − 20 = 260 天 ≈ 37 周，满足 ≥ 36。返回首页的方式若与导航结构不符（分娩页是首页 NavigationStack 里 push 进来的），用 `app.tabBars.buttons["首页"].tap()` 再 tap 一次回到根。

- [ ] **Step 2: 运行 UI 用例**

先确认本地栈在跑（`make dev`）。
Run: `cd apps/ios && xcodebuild test -project AimApp.xcodeproj -scheme AimApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:AimAppUITests/CoreJourneyUITests/testLaborModeTimesContractionsAndAnnouncesTheHospitalTrip 2>&1 | tail -30`
Expected: PASS。失败时看 xcresult 截图定位，修界面或用例，不弱化断言。

再跑一遍胎动用例 `testCountingFetalMovementFromHome`，确认首页加卡片后它仍然通过。

- [ ] **Step 3: 全量验证**

Run:
```bash
make verify
cd services/agent && npm test
```
iOS 全部单元测试再跑一遍。Expected: 全部通过。已知两条既有 UI 失败与本计划无关，不需要跑全量 UI。

- [ ] **Step 4: 更新路线图**

`docs/superpowers/2026-10-roadmap.md`：
- 第 7 项状态改为「✅ 已完成并合并本地 development」，规格 / 计划列填 `specs/2026-10-12-labor-mode-design.md、plans/2026-10-12-labor-mode.md`。
- 「当前接续点」把下一主线改为第 8 项「情绪关照」。
- 「部署约束」加一条：后端先于 iOS 上线没问题（旧 App 把两种新类型解码为 unknown）；百科 `birth.when-to-go` 改动未经产品负责人复看。

- [ ] **Step 5: 提交**

```bash
git add apps/ios/AimApp/UITests/CoreJourneyUITests.swift docs/superpowers/2026-10-roadmap.md
git commit -m "test(ios): 分娩模式端到端用例；路线图第 7 项完成"
```
