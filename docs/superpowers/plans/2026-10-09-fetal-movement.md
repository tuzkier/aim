# 胎动计数 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 孕妈（或替她按的家人）能在 App 里用「数到 10 次」法数胎动，每次结果存进家庭档案，能看历史与趋势，异常时得到明确的就医提示。

**Architecture:** 后端新增记录类型 `fetal_movement`（复用 records 表与接口，只加校验）。iOS 端分三层：纯数据的计数器与统计（不碰计时器，所有判断按「开始时间 + 当前时间」计算）、`FetalMovementStore`（本地断点、保存与重试、历史）、界面（计数页、安全提示页、胎动页、首页卡、资料库卡、百科条目按钮）。Store 通过 SwiftUI environment 注入，入口视图不改签名。

**Tech Stack:** FastAPI + pytest；Eve agent（TypeScript + zod）；SwiftUI（iOS 17+，`@Observable`）+ XCTest / XCUITest。

规格：`docs/superpowers/specs/2026-10-09-fetal-movement-design.md`。

## Global Constraints

- 所有面向用户的文字、注释、提交信息用简体中文。
- 方法：「数到 10 次」。目标 `10` 次；窗口 2 小时（`7200` 秒）；单次记录最长 3 小时（`10800` 秒）；防误触去重间隔 `3` 秒（UI 测试用启动参数 `-fetal-dedupe-zero` 设为 0）。
- 判断标准（2026-10-09 审核确定）：2 小时内不足 10 次，或比自己平时明显减少（约少一半）→ 尽快联系医院；任何时候感觉胎动明显变少、变弱或停止 → 不用数完，立即联系医院。
- 「和平时比」：平时 = 最近 7 次 `reached` 记录用时的中位数，至少 3 次才计算；本次用时 > 平时 × 2 且 > 1800 秒时给出「建议尽快联系医院」的提醒（提醒色，不用危险红）。
- 完成页不说「正常」，只说「已记录」，并始终保留「感觉不对就联系医院」。
- 记录：`record_type = "fetal_movement"`，`occurred_at` = 开始时间，默认家庭可见；`structured_data = {duration_seconds, count, target, outcome, taps}`；`outcome ∈ {reached, under, stopped}`；`title` 为客户端生成的一句摘要。
- 首页卡与资料库卡：孕 28 周起显示（资料库卡在已有胎动记录时也显示）。
- iOS 新文件手工登记 `apps/ios/AimApp.xcodeproj/project.pbxproj` 四处（PBXBuildFile、PBXFileReference、所在 group 的 children、对应 target 的 Sources 构建阶段），编号从 `…160` 起，格式照抄 `Features/Library/EncyclopediaModels.swift`（App，155）与 `Tests/EncyclopediaCatalogTests.swift`（测试，159）的四处登记。用前先 `grep` 确认编号未被占用。
- 项目里有自家的 `TimelineView` 类型；需要 SwiftUI 的定时刷新时必须写 `SwiftUI.TimelineView`。
- 模拟器用 iPhone 18 Pro；UI 测试连本地 `make dev` 栈；已知两条既有 UI 用例失败（`testGlobalAgentButtonShowsCurrentTabContext`、`testAPastConversationCanBeReopenedFromHistory`），与本计划无关。

## 文件结构

API（`services/api/`）：
- Modify `src/aim_api/contexts/records/domain/record.py` —— 新类型与校验。
- Modify `src/aim_api/composition/family/activity.py` —— 类型显示名。
- Create `tests/domain/records/test_fetal_movement.py`；Modify `tests/integration/records/test_records_api.py`。
- 重新生成 `contracts/public-api/openapi.json`（`RecordType` 枚举进入了契约）。

Agent（`services/agent/`）：
- Modify `agent/tools/list_records.ts`、`agent/instructions.md`。

iOS（`apps/ios/AimApp/`）：
- Modify `Features/Records/RecordModels.swift`、`Generated/OpenAPI/Models.swift`、`Features/Records/RecordsView.swift`、`Features/Records/RecordDetailView.swift`、`Features/Records/RecordComposerView.swift`、`Clients/BusinessAPIClient/BusinessRepository.swift` —— 新记录类型贯通。
- Create `Features/FetalMovement/FetalMovementModels.swift`（160）—— 计数器、结果、会话、格式化、统计。纯数据。
- Create `Features/FetalMovement/FetalMovementStore.swift`（161）—— 断点、保存、重试、历史。
- Create `Features/FetalMovement/FetalMovementCounterView.swift`（162）—— 计数页、完成页、安全提示页、说明页、文案常量。
- Create `Features/FetalMovement/FetalMovementView.swift`（163）—— 胎动页（今天、趋势、历史）与首页卡。
- Create `Tests/FetalMovementModelsTests.swift`（164）、`Tests/FetalMovementStoreTests.swift`（165）。
- Modify `App/AimApp.swift`、`Features/Home/HomeDashboardView.swift`、`Features/Library/LibraryCatalog.swift`、`Features/Library/LibraryView.swift`、`Features/Library/LibraryCategoryDetail.swift`、`Features/Library/EncyclopediaEntryView.swift`、`UITests/CoreJourneyUITests.swift`。

---

### Task 1: 后端记录类型 `fetal_movement`

**Files:**
- Modify: `services/api/src/aim_api/contexts/records/domain/record.py`（`RecordType` :13-19；常量区 :104 附近；`_validate_payload` :211-276）
- Modify: `services/api/src/aim_api/composition/family/activity.py:23-30`
- Test: `services/api/tests/domain/records/test_fetal_movement.py`、`services/api/tests/integration/records/test_records_api.py`

**Interfaces:**
- Produces：`RecordType.fetal_movement = "fetal_movement"`；`POST /api/v1/pregnancies/{id}/records` 接受 `type="fetal_movement"`，非法返回 409；`GET …/records?type=fetal_movement` 可筛选。

- [ ] **Step 1: 写领域测试（先失败）**

`services/api/tests/domain/records/test_fetal_movement.py`：

```python
from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from aim_api.contexts.records.domain.record import (
    Record,
    RecordType,
    RecordValidationError,
    RecordVisibility,
)


def valid(**overrides) -> dict:
    data = {
        "duration_seconds": 1920,
        "count": 10,
        "target": 10,
        "outcome": "reached",
        "taps": [30, 200, 400, 600, 800, 1000, 1200, 1500, 1700, 1920],
    }
    data.update(overrides)
    return data


def make(structured_data: dict) -> Record:
    return Record.create(
        pregnancy_id=uuid4(),
        family_id=uuid4(),
        author_account_id=uuid4(),
        record_type=RecordType.fetal_movement,
        occurred_at=datetime.now(UTC),
        visibility=RecordVisibility.family,
        title="数胎动 10 次 · 32 分钟",
        content=None,
        structured_data=structured_data,
    )


class TestFetalMovement:
    def test_a_reached_session_is_valid(self):
        assert make(valid()).structured_data["outcome"] == "reached"

    def test_an_under_session_needs_two_full_hours(self):
        make(valid(outcome="under", count=6, duration_seconds=7200, taps=[10, 20, 30, 40, 50, 60]))
        with pytest.raises(RecordValidationError):
            make(valid(outcome="under", count=6, duration_seconds=7199, taps=[10, 20, 30, 40, 50, 60]))

    def test_under_must_have_fewer_than_target(self):
        with pytest.raises(RecordValidationError):
            make(valid(outcome="under", duration_seconds=7200))

    def test_reached_needs_at_least_target(self):
        with pytest.raises(RecordValidationError):
            make(valid(count=9, taps=[1, 2, 3, 4, 5, 6, 7, 8, 9]))

    def test_a_stopped_session_has_no_count_requirement(self):
        make(valid(outcome="stopped", count=0, duration_seconds=90, taps=[]))

    @pytest.mark.parametrize("duration", [-1, 10801, 12.5, True, "60"])
    def test_duration_must_be_an_integer_within_three_hours(self, duration):
        with pytest.raises(RecordValidationError):
            make(valid(duration_seconds=duration))

    @pytest.mark.parametrize("count", [-1, 201, True, "10"])
    def test_count_must_be_an_integer_in_range(self, count):
        with pytest.raises(RecordValidationError):
            make(valid(count=count))

    @pytest.mark.parametrize("target", [6, 12, True, None])
    def test_target_is_fixed_at_ten(self, target):
        with pytest.raises(RecordValidationError):
            make(valid(target=target))

    def test_unknown_outcome_is_rejected(self):
        with pytest.raises(RecordValidationError):
            make(valid(outcome="normal"))

    def test_taps_must_match_count(self):
        with pytest.raises(RecordValidationError):
            make(valid(taps=[1, 2, 3]))

    def test_taps_must_not_go_backwards_or_past_the_duration(self):
        with pytest.raises(RecordValidationError):
            make(valid(taps=[30, 20, 400, 600, 800, 1000, 1200, 1500, 1700, 1920]))
        with pytest.raises(RecordValidationError):
            make(valid(taps=[30, 200, 400, 600, 800, 1000, 1200, 1500, 1700, 1921]))

    def test_equal_neighbouring_taps_are_allowed(self):
        """秒级取整后，相邻两次点按可能落在同一秒。"""
        make(valid(taps=[30, 30, 400, 600, 800, 1000, 1200, 1500, 1700, 1920]))
```

先打开 `tests/domain/records/test_question_and_checklist.py` 看 `Record.create` 的真实参数名（上面按常见命名写，**以现有代码为准调整 `make()`**），并照它的 import 写法调整。

Run: `cd services/api && PYTHONPATH=src python3 -m pytest tests/domain/records/test_fetal_movement.py -q`
Expected: FAIL（`RecordType` 没有 `fetal_movement`）

- [ ] **Step 2: 实现校验**

`RecordType` 加一行：

```python
    fetal_movement = "fetal_movement"
```

常量区（`CHECKUP_METRIC_RANGES` 附近）加：

```python
    # 胎动计数用「数到 10 次」法。目标写进每条记录，将来换方法时旧数据仍可解读。
    FETAL_MOVEMENT_TARGET: ClassVar[int] = 10
    # 2 小时内不足 10 次需要尽快就医；记录最长 3 小时，超出说明客户端计时出了问题。
    FETAL_MOVEMENT_WINDOW_SECONDS: ClassVar[int] = 2 * 60 * 60
    FETAL_MOVEMENT_MAX_SECONDS: ClassVar[int] = 3 * 60 * 60
    FETAL_MOVEMENT_OUTCOMES: ClassVar[frozenset[str]] = frozenset({"reached", "under", "stopped"})
```

`_validate_payload` 中，最后的 `raise RecordValidationError(f"unsupported record type…")` 之前加：

```python
        if record_type is RecordType.fetal_movement:
            cls._validate_fetal_movement(structured_data)
            return
```

并新增类方法：

```python
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
            if isinstance(offset, bool) or not isinstance(offset, int) or not previous <= offset <= duration:
                raise RecordValidationError(
                    "fetal movement taps must be non-decreasing seconds within the duration"
                )
            previous = offset
```

（若该行超过 100 字符，按 ruff 拆行。）

`activity.py` 的 `_RECORD_TYPE_NAMES` 加 `"fetal_movement": "胎动",`。

Run: `cd services/api && PYTHONPATH=src python3 -m pytest tests/domain/records/test_fetal_movement.py -q`
Expected: 全部通过

- [ ] **Step 3: 集成测试**

在 `tests/integration/records/test_records_api.py` 末尾加（沿用文件内 `_phone`、`_headers`、`_create_pregnancy`、`_create_record`）：

```python
def test_fetal_movement_records_can_be_created_filtered_and_rejected() -> None:
    account_id = str(uuid4())
    phone = _phone(account_id)
    headers = _headers(account_id, phone)
    with TestClient(create_app()) as client:
        _, pregnancy_id = _create_pregnancy(client, account_id, phone)
        created = _create_record(
            client, pregnancy_id, headers,
            type="fetal_movement", title="数胎动 10 次 · 32 分钟",
            structured_data={
                "duration_seconds": 1920, "count": 10, "target": 10, "outcome": "reached",
                "taps": [30, 200, 400, 600, 800, 1000, 1200, 1500, 1700, 1920],
            },
        )
        rejected = _create_record(
            client, pregnancy_id, headers,
            type="fetal_movement",
            structured_data={"duration_seconds": 60, "count": 1, "target": 6,
                             "outcome": "stopped", "taps": [5]},
        )
        listed = client.get(
            f"/api/v1/pregnancies/{pregnancy_id}/records",
            params={"type": "fetal_movement"}, headers=headers,
        )

    assert created.status_code == 201, created.text
    assert created.json()["structured_data"]["outcome"] == "reached"
    assert rejected.status_code == 409, rejected.text
    assert listed.status_code == 200, listed.text
    assert [r["type"] for r in listed.json()["records"]] == ["fetal_movement"]
```

（`_create_record` 的默认字段若与上面冲突，以文件内 helper 的实际签名为准；列表响应的键名若不是 `records`/`type`，按现有用例调整。）

- [ ] **Step 4: 全量测试、契约、lint**

Run: `cd services/api && PYTHONPATH=src python3 -m pytest -q && make contracts && git diff --stat ../../contracts && uvx ruff check src/aim_api/contexts/records/domain/record.py src/aim_api/composition/family/activity.py tests/domain/records/test_fetal_movement.py`
Expected: 全部通过；`contracts/public-api/openapi.json` 的 `RecordType` 枚举多出 `fetal_movement`（agent-tools 契约若同样包含该枚举也会变化，一并提交）。

- [ ] **Step 5: 提交**

```bash
git add services/api contracts
git commit -m "feat(api): 新增胎动计数记录类型与校验"
```

---

### Task 2: AIM 能读胎动记录

**Files:**
- Modify: `services/agent/agent/tools/list_records.ts:9`
- Modify: `services/agent/agent/instructions.md`（:28-33 的症状与安全段落之后）

**Interfaces:**
- Consumes：Task 1 的 `fetal_movement` 类型（API 侧 `RecordType(...)` 直接转换，无需改路由）。

- [ ] **Step 1: 放开类型**

`list_records.ts` 第 9 行改为：

```ts
  type: z.enum(["symptom", "checkup", "note", "fetal_movement"]).optional(),
```

（只改 `list_records`；`create_record.ts` 不加——胎动只能在计数页实时产生。）

- [ ] **Step 2: 指令**

在 `instructions.md` 症状与安全段落之后加一段（保持该文件现有语言风格；若全文是英文就用英文写，含义一致）：

```markdown
Fetal movement: records of type `fetal_movement` are kick counts made in the app with the
"count to 10" method (`count`, `duration_seconds`, `outcome` = reached / under / stopped).
When the user asks about fetal movement, read their recent counts with `list_records`
(type `fetal_movement`) first. If the user describes movement that is noticeably less, weaker
or has stopped compared with usual, or a count under 10 within 2 hours, tell them first and
clearly to contact their hospital or go to obstetric emergency now — do not analyse, reassure
or suggest waiting. You cannot count or create fetal movement records; point them to the
count screen in the app.
```

- [ ] **Step 3: 测试**

Run: `make -C services/agent test`
Expected: 全部通过（`runtime-gate` 测试不受影响，未新增工具）

- [ ] **Step 4: 提交**

```bash
git add services/agent
git commit -m "feat(agent): 能读胎动计数记录；胎动减少时优先建议就医"
```

---

### Task 3: iOS 新记录类型贯通

**Files:**
- Modify: `apps/ios/AimApp/Features/Records/RecordModels.swift`（`RecordType` :3-44；`RecordStructuredData` :110-118）
- Modify: `apps/ios/AimApp/Generated/OpenAPI/Models.swift`（`APIRecordStructuredDataDTO` :218-345）
- Modify: `apps/ios/AimApp/Features/Records/RecordsView.swift:4-75`
- Modify: `apps/ios/AimApp/Features/Records/RecordDetailView.swift:94` 附近 `contentSection`
- Modify: `apps/ios/AimApp/Features/Records/RecordComposerView.swift:128`、`:250`、`:278`
- Modify: `apps/ios/AimApp/Clients/BusinessAPIClient/BusinessRepository.swift:657` 附近 `validate`
- Test: `apps/ios/AimApp/Tests/FetalMovementModelsTests.swift`（新文件，编号 164；本任务只放编解码用例，Task 4 往里追加）

**Interfaces:**
- Produces：
  - `RecordType.fetalMovement`（rawValue `"fetal_movement"`，displayName `"胎动"`，symbolName `"hand.tap"`）
  - `enum FetalMovementOutcome: String, Codable, Sendable { case reached, under, stopped }`
  - `struct FetalMovementRecordData: Codable, Equatable, Sendable { let durationSeconds: Int; let count: Int; let target: Int; let outcome: FetalMovementOutcome; let taps: [Int] }`
  - `RecordStructuredData.fetalMovement(FetalMovementRecordData)`
  - `FetalMovementFormat.duration(_ seconds: Int) -> String`、`FetalMovementFormat.summary(_ data: FetalMovementRecordData) -> String`

- [ ] **Step 1: 写失败的测试**

`Tests/FetalMovementModelsTests.swift`（登记编号 164，测试 target）：

```swift
import XCTest
@testable import AimApp

final class FetalMovementModelsTests: XCTestCase {
    func testRecordTypeRoundTripsItsRawValue() {
        XCTAssertEqual(RecordType(rawValue: "fetal_movement"), .fetalMovement)
        XCTAssertEqual(RecordType.fetalMovement.rawValue, "fetal_movement")
        XCTAssertEqual(RecordType.fetalMovement.displayName, "胎动")
    }

    func testStructuredDataDecodesFromTheAPIShape() throws {
        let json = """
        {"duration_seconds":1920,"count":10,"target":10,"outcome":"reached","taps":[1,2,3,4,5,6,7,8,9,1920]}
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(APIRecordStructuredDataDTO.self, from: json)

        guard case let .fetalMovement(data) = dto.recordData(for: .fetalMovement) else {
            return XCTFail("应当解码为胎动")
        }
        XCTAssertEqual(data.durationSeconds, 1920)
        XCTAssertEqual(data.outcome, .reached)
        XCTAssertEqual(data.taps.count, 10)
    }

    func testUnknownOutcomeFallsBackToUnknownRecordData() throws {
        let json = """
        {"duration_seconds":60,"count":1,"target":10,"outcome":"normal","taps":[5]}
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(APIRecordStructuredDataDTO.self, from: json)
        XCTAssertEqual(dto.recordData(for: .fetalMovement), .unknown)
    }

    func testStructuredDataEncodesTheAPIKeys() throws {
        let data = FetalMovementRecordData(durationSeconds: 7200, count: 6, target: 10, outcome: .under, taps: [1, 2, 3, 4, 5, 6])
        let encoded = try JSONEncoder().encode(APIRecordStructuredDataDTO(recordData: .fetalMovement(data)))
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertEqual(object?["duration_seconds"] as? Int, 7200)
        XCTAssertEqual(object?["outcome"] as? String, "under")
        XCTAssertEqual(object?["target"] as? Int, 10)
        XCTAssertEqual((object?["taps"] as? [Int])?.count, 6)
    }

    func testFormatting() {
        XCTAssertEqual(FetalMovementFormat.duration(40), "不到 1 分钟")
        XCTAssertEqual(FetalMovementFormat.duration(1920), "32 分钟")
        XCTAssertEqual(FetalMovementFormat.duration(1921), "33 分钟")
        XCTAssertEqual(FetalMovementFormat.duration(7200), "2 小时")
        XCTAssertEqual(FetalMovementFormat.duration(4500), "1 小时 15 分钟")
        XCTAssertEqual(
            FetalMovementFormat.summary(.init(durationSeconds: 1920, count: 10, target: 10, outcome: .reached, taps: [])),
            "10 次 · 32 分钟")
        XCTAssertEqual(
            FetalMovementFormat.summary(.init(durationSeconds: 7200, count: 6, target: 10, outcome: .under, taps: [])),
            "2 小时 6 次 · 不足 10 次")
        XCTAssertEqual(
            FetalMovementFormat.summary(.init(durationSeconds: 600, count: 4, target: 10, outcome: .stopped, taps: [])),
            "4 次 · 10 分钟 · 未数完")
    }
}
```

（`JSONEncoder()` 若对 `APIRecordStructuredDataDTO` 的 nil 字段输出 null 也无妨，断言只看存在的键。）

Run（iPhone 18 Pro）: `xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppTests/FetalMovementModelsTests 2>&1 | grep -E "error:|Executed" | head`
Expected: 编译失败（`fetalMovement` 不存在）

- [ ] **Step 2: 模型**

`RecordModels.swift`：
- `RecordType` 加 `case fetalMovement`；`init(rawValue:)` 加 `case "fetal_movement": self = .fetalMovement`；`rawValue` 加 `case .fetalMovement: return "fetal_movement"`。
- 在 `QuestionRecordData` 附近加：

```swift
enum FetalMovementOutcome: String, Codable, Sendable {
    /// 数到 10 次。
    case reached
    /// 满 2 小时不足 10 次。
    case under
    /// 中途手动结束。
    case stopped
}

/// 一次「数到 10 次」胎动计数。开始时间就是记录的 occurredAt。
struct FetalMovementRecordData: Codable, Equatable, Sendable {
    let durationSeconds: Int
    let count: Int
    let target: Int
    let outcome: FetalMovementOutcome
    /// 每次计数距开始的秒数。
    let taps: [Int]
}

enum FetalMovementFormat {
    /// 「不到 1 分钟」「32 分钟」「1 小时 15 分钟」「2 小时」。分钟向上取整：
    /// 32 分 1 秒显示 33 分钟，避免把慢的说成快的。
    static func duration(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "不到 1 分钟" }
        let minutes = (seconds + 59) / 60
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(minutes) 分钟" }
        return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分钟"
    }

    static func summary(_ data: FetalMovementRecordData) -> String {
        switch data.outcome {
        case .reached: "\(data.count) 次 · \(duration(data.durationSeconds))"
        case .under: "\(duration(data.durationSeconds)) \(data.count) 次 · 不足 \(data.target) 次"
        case .stopped: "\(data.count) 次 · \(duration(data.durationSeconds)) · 未数完"
        }
    }
}
```

- `RecordStructuredData` 加 `case fetalMovement(FetalMovementRecordData)`。

- [ ] **Step 3: DTO 编解码**

`Generated/OpenAPI/Models.swift` 的 `APIRecordStructuredDataDTO`：
- 加属性 `let durationSeconds: Int?`、`let count: Int?`、`let target: Int?`、`let outcome: String?`、`let taps: [Int]?`，以及 init 参数（默认 nil）与赋值。
- `CodingKeys` 加 `case count, target, outcome, taps` 与 `case durationSeconds = "duration_seconds"`。
- `recordData(for:)` 加：

```swift
        case .fetalMovement:
            guard let durationSeconds, let count, let target, let taps,
                  let outcome = outcome.flatMap(FetalMovementOutcome.init(rawValue:)) else { return .unknown }
            return .fetalMovement(FetalMovementRecordData(
                durationSeconds: durationSeconds, count: count, target: target, outcome: outcome, taps: taps))
```

- `init(recordData:)` 加：

```swift
        case let .fetalMovement(data):
            self.init(durationSeconds: data.durationSeconds, count: data.count, target: data.target,
                      outcome: data.outcome.rawValue, taps: data.taps)
```

- [ ] **Step 4: 补齐所有 switch**

- `RecordsView.swift`：`displayName` → `case .fetalMovement: "胎动"`；`symbolName` → `case .fetalMovement: "hand.tap"`；`displayTitle` → `case .fetalMovement: "数胎动"`；`displaySummary` → `case let .fetalMovement(data): return FetalMovementFormat.summary(data)`。
- `RecordDetailView.swift` 的 `contentSection` 加：

```swift
        case let .fetalMovement(data):
            Section("胎动") {
                LabeledContent("次数", value: "\(data.count) 次")
                LabeledContent("用时", value: FetalMovementFormat.duration(data.durationSeconds))
                LabeledContent("结果", value: FetalMovementFormat.summary(data))
            }
```

- `RecordComposerView.swift` 三处把 `.fetalMovement` 并进 `.question, .checklist, .knowledge` 那一组（胎动不能在新增记录面板里手填）。
- `BusinessRepository.swift` `validate` 的配对列表加 `(.fetalMovement, .fetalMovement)`。
- 其它编译器报 non-exhaustive 的 switch，按「显示为胎动、不可手动编辑」的语义补齐。

- [ ] **Step 5: 跑测试**

Run: 同 Step 1，再跑一次完整 `-only-testing:AimAppTests`
Expected: `FetalMovementModelsTests` 5 条通过；全部单元测试 0 失败

- [ ] **Step 6: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): 胎动记录类型的模型、编解码与显示"
```

---

### Task 4: 计数器与统计（纯数据）

**Files:**
- Create: `apps/ios/AimApp/Features/FetalMovement/FetalMovementModels.swift`（160，App target，放进新建的 `FetalMovement` group——照抄 `Features/Home` group 在 pbxproj 中的写法建一个 group，并挂到 `Features` group 下）
- Test: `apps/ios/AimApp/Tests/FetalMovementModelsTests.swift`（追加）

**Interfaces:**
- Consumes：Task 3 的 `FetalMovementOutcome`、`FetalMovementRecordData`、`FetalMovementFormat`、`RecordItem`、`RecordDraft`。
- Produces：
  - `struct FetalMovementCounter: Codable, Equatable, Sendable`：`static let target = 10`、`static let window: TimeInterval = 7200`、`static let defaultDedupeInterval: TimeInterval = 3`；`init(startedAt: Date, dedupeInterval: TimeInterval = defaultDedupeInterval)`；`startedAt`、`dedupeInterval`、`taps: [TimeInterval]`、`count`；`elapsed(at:) -> TimeInterval`、`isExpired(at:) -> Bool`、`mutating tap(at:) -> TapResult`、`result(at:) -> FetalMovementResult`；`enum TapResult { counted, ignored, reachedTarget, expired }`
  - `struct FetalMovementResult: Codable, Equatable, Sendable { startedAt: Date; durationSeconds: Int; count: Int; outcome: FetalMovementOutcome; taps: [Int] }`，`recordData`、`title`、`draft: RecordDraft`
  - `struct FetalMovementSession: Identifiable, Equatable, Sendable { id: UUID; startedAt: Date; data: FetalMovementRecordData }`，`init?(record: RecordItem)`
  - `struct FetalMovementDay: Equatable, Sendable { date: Date; reachedSeconds: Int?; hadUnder: Bool }`
  - `enum FetalMovementInsights`：`baselineSeconds(_:) -> Int?`、`isSlow(durationSeconds:baselineSeconds:) -> Bool`、`latest(onDayOf:in:calendar:) -> FetalMovementSession?`、`dailyTrend(_:days:now:calendar:) -> [FetalMovementDay]`

- [ ] **Step 1: 追加失败的测试**

在 `FetalMovementModelsTests` 里追加：

```swift
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func counter(dedupe: TimeInterval = 3) -> FetalMovementCounter {
        FetalMovementCounter(startedAt: start, dedupeInterval: dedupe)
    }

    func testTapsWithinTheDedupeIntervalAreIgnored() {
        var c = counter()
        XCTAssertEqual(c.tap(at: start.addingTimeInterval(10)), .counted)
        XCTAssertEqual(c.tap(at: start.addingTimeInterval(12)), .ignored)
        XCTAssertEqual(c.tap(at: start.addingTimeInterval(13)), .counted)
        XCTAssertEqual(c.count, 2)
    }

    func testTheTenthTapReachesTheTargetAndEndsAtThatMoment() {
        var c = counter()
        for i in 1...9 { XCTAssertEqual(c.tap(at: start.addingTimeInterval(Double(i * 60))), .counted) }
        XCTAssertEqual(c.tap(at: start.addingTimeInterval(1920.4)), .reachedTarget)

        let result = c.result(at: start.addingTimeInterval(5000))
        XCTAssertEqual(result.outcome, .reached)
        XCTAssertEqual(result.durationSeconds, 1921)
        XCTAssertEqual(result.count, 10)
        XCTAssertEqual(result.taps.last, 1920)
        XCTAssertEqual(c.tap(at: start.addingTimeInterval(2000)), .reachedTarget, "数满后不再计数")
    }

    func testTwoHoursWithoutTenIsUnder() {
        var c = counter()
        for i in 1...6 { _ = c.tap(at: start.addingTimeInterval(Double(i * 600))) }
        let late = start.addingTimeInterval(7200)
        XCTAssertTrue(c.isExpired(at: late))
        XCTAssertEqual(c.tap(at: late), .expired)

        let result = c.result(at: start.addingTimeInterval(9000))
        XCTAssertEqual(result.outcome, .under)
        XCTAssertEqual(result.durationSeconds, 7200, "超过 2 小时才回来，也按满 2 小时记")
        XCTAssertEqual(result.count, 6)
    }

    func testStoppingEarlyRecordsTheElapsedTime() {
        var c = counter()
        _ = c.tap(at: start.addingTimeInterval(30))
        let result = c.result(at: start.addingTimeInterval(600.9))
        XCTAssertEqual(result.outcome, .stopped)
        XCTAssertEqual(result.durationSeconds, 600)
        XCTAssertEqual(result.taps, [30])
    }

    func testTheCounterSurvivesARoundTripThroughJSON() throws {
        var c = counter()
        _ = c.tap(at: start.addingTimeInterval(42))
        let restored = try JSONDecoder().decode(FetalMovementCounter.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(restored, c)
    }

    func testResultBuildsAFamilyVisibleDraft() {
        let result = FetalMovementResult(startedAt: start, durationSeconds: 1920, count: 10, outcome: .reached, taps: Array(1...10))
        let draft = result.draft
        XCTAssertEqual(draft.type, .fetalMovement)
        XCTAssertEqual(draft.occurredAt, start)
        XCTAssertEqual(draft.visibility, .family)
        XCTAssertEqual(draft.title, "数胎动 10 次 · 32 分钟")
        XCTAssertEqual(draft.structuredData, .fetalMovement(result.recordData))
    }

    private func session(_ daysAgo: Int, hour: Int = 20, seconds: Int, outcome: FetalMovementOutcome = .reached) -> FetalMovementSession {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: start)!
        let at = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return FetalMovementSession(
            id: UUID(), startedAt: at,
            data: FetalMovementRecordData(durationSeconds: seconds, count: outcome == .reached ? 10 : 6,
                                          target: 10, outcome: outcome, taps: []))
    }

    func testBaselineIsTheMedianOfTheLastSevenReachedSessions() {
        XCTAssertNil(FetalMovementInsights.baselineSeconds([session(1, seconds: 600), session(2, seconds: 700)]),
                     "不足 3 次不算平时")
        let sessions = [
            session(1, seconds: 600), session(2, seconds: 900), session(3, seconds: 700),
            session(4, seconds: 7200, outcome: .under),
            session(5, seconds: 800), session(6, seconds: 650), session(7, seconds: 750),
            session(8, seconds: 720), session(9, seconds: 5000),
        ]
        // 取最近 7 次 reached：600 900 700 800 650 750 720 → 中位数 720；第 9 天的 5000 不在其中。
        XCTAssertEqual(FetalMovementInsights.baselineSeconds(sessions), 720)
    }

    func testSlowNeedsBothDoubleTheBaselineAndHalfAnHour() {
        XCTAssertTrue(FetalMovementInsights.isSlow(durationSeconds: 2000, baselineSeconds: 900))
        XCTAssertFalse(FetalMovementInsights.isSlow(durationSeconds: 1700, baselineSeconds: 600), "不到 30 分钟不提醒")
        XCTAssertFalse(FetalMovementInsights.isSlow(durationSeconds: 1900, baselineSeconds: 1000), "没到平时的 2 倍")
        XCTAssertFalse(FetalMovementInsights.isSlow(durationSeconds: 5000, baselineSeconds: nil))
    }

    func testDailyTrendTakesTheFirstReachedSessionOfEachDayAndFlagsUnder() {
        let calendar = Calendar(identifier: .gregorian)
        let sessions = [
            session(0, hour: 21, seconds: 900),
            session(0, hour: 9, seconds: 600),
            session(1, hour: 20, seconds: 7200, outcome: .under),
        ]
        let trend = FetalMovementInsights.dailyTrend(sessions, days: 3, now: start, calendar: calendar)

        XCTAssertEqual(trend.count, 3)
        XCTAssertEqual(trend.last?.reachedSeconds, 600, "当天取最早完成的那次")
        XCTAssertEqual(trend[1].reachedSeconds, nil)
        XCTAssertTrue(trend[1].hadUnder)
        XCTAssertEqual(trend.first?.reachedSeconds, nil)
        XCTAssertFalse(trend.first?.hadUnder ?? true)
    }

    func testLatestSessionOfTheDay() {
        let calendar = Calendar(identifier: .gregorian)
        let sessions = [session(0, hour: 9, seconds: 600), session(0, hour: 21, seconds: 900), session(1, seconds: 500)]
        XCTAssertEqual(FetalMovementInsights.latest(onDayOf: start, in: sessions, calendar: calendar)?.data.durationSeconds, 900)
    }
```

（`session(0, hour:)` 以 `start` 所在日为「今天」。若 `start` 的本地时区导致日期边界与断言不符，把测试里的 `Calendar` 固定 `timeZone = TimeZone(identifier: "Asia/Shanghai")!`，并在 `session()` 与断言中使用同一个 calendar。）

Run: `… -only-testing:AimAppTests/FetalMovementModelsTests …`
Expected: 编译失败（`FetalMovementCounter` 不存在）

- [ ] **Step 2: 实现**

`Features/FetalMovement/FetalMovementModels.swift`：

```swift
import Foundation

/// 一次「数到 10 次」胎动计数。
///
/// 纯数据、不碰计时器：所有判断都以开始时间和传入的「现在」计算。
/// App 被系统挂起或杀掉后，从本地恢复同一个值就能接着算，计时也不会停。
struct FetalMovementCounter: Codable, Equatable, Sendable {
    static let target = 10
    static let window: TimeInterval = 2 * 60 * 60
    /// 一阵连续的动只算一次；这里只防手抖连点，不做更长的自动合并——
    /// 规则不透明，用户会困惑数字为什么没变。
    static let defaultDedupeInterval: TimeInterval = 3

    enum TapResult: Equatable, Sendable { case counted, ignored, reachedTarget, expired }

    let startedAt: Date
    let dedupeInterval: TimeInterval
    private(set) var taps: [TimeInterval] = []

    init(startedAt: Date, dedupeInterval: TimeInterval = Self.defaultDedupeInterval) {
        self.startedAt = startedAt
        self.dedupeInterval = dedupeInterval
    }

    var count: Int { taps.count }

    func elapsed(at now: Date) -> TimeInterval { max(0, now.timeIntervalSince(startedAt)) }

    func isExpired(at now: Date) -> Bool { count < Self.target && elapsed(at: now) >= Self.window }

    mutating func tap(at now: Date) -> TapResult {
        guard count < Self.target else { return .reachedTarget }
        if isExpired(at: now) { return .expired }
        let offset = elapsed(at: now)
        if let last = taps.last, offset - last < dedupeInterval { return .ignored }
        taps.append(offset)
        return count == Self.target ? .reachedTarget : .counted
    }

    func result(at now: Date) -> FetalMovementResult {
        let seconds = taps.map { Int($0.rounded(.down)) }
        if count >= Self.target {
            return FetalMovementResult(
                startedAt: startedAt, durationSeconds: Int(taps[Self.target - 1].rounded(.up)),
                count: count, outcome: .reached, taps: seconds)
        }
        if isExpired(at: now) {
            return FetalMovementResult(
                startedAt: startedAt, durationSeconds: Int(Self.window),
                count: count, outcome: .under, taps: seconds)
        }
        return FetalMovementResult(
            startedAt: startedAt, durationSeconds: Int(elapsed(at: now).rounded(.down)),
            count: count, outcome: .stopped, taps: seconds)
    }
}

struct FetalMovementResult: Codable, Equatable, Sendable {
    let startedAt: Date
    let durationSeconds: Int
    let count: Int
    let outcome: FetalMovementOutcome
    let taps: [Int]

    var recordData: FetalMovementRecordData {
        FetalMovementRecordData(
            durationSeconds: durationSeconds, count: count, target: FetalMovementCounter.target,
            outcome: outcome, taps: taps)
    }

    /// 家庭动态直接显示它：「爸爸 记了「数胎动 10 次 · 32 分钟」」。
    var title: String { "数胎动 " + FetalMovementFormat.summary(recordData) }

    var draft: RecordDraft {
        RecordDraft(
            type: .fetalMovement, occurredAt: startedAt, visibility: .family,
            title: title, content: nil, structuredData: .fetalMovement(recordData))
    }
}

/// 档案里的一次计数。
struct FetalMovementSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let data: FetalMovementRecordData

    init(id: UUID, startedAt: Date, data: FetalMovementRecordData) {
        self.id = id
        self.startedAt = startedAt
        self.data = data
    }

    init?(record: RecordItem) {
        guard case let .fetalMovement(data) = record.structuredData else { return nil }
        self.init(id: record.id, startedAt: record.occurredAt, data: data)
    }
}

struct FetalMovementDay: Equatable, Sendable {
    let date: Date
    /// 当天第一次数到 10 次的用时；没有完成的计数为 nil。
    let reachedSeconds: Int?
    let hadUnder: Bool
}

enum FetalMovementInsights {
    static let baselineWindow = 7
    static let baselineMinimum = 3
    static let slowFloorSeconds = 30 * 60

    /// 「平时」：最近 7 次数到 10 次的用时中位数，至少 3 次才算。
    static func baselineSeconds(_ sessions: [FetalMovementSession]) -> Int? {
        let recent = sessions
            .filter { $0.data.outcome == .reached }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(baselineWindow)
            .map(\.data.durationSeconds)
            .sorted()
        guard recent.count >= baselineMinimum else { return nil }
        let middle = recent.count / 2
        return recent.count.isMultiple(of: 2)
            ? (recent[middle - 1] + recent[middle]) / 2
            : recent[middle]
    }

    /// 数到 10 次的用时翻倍，大致相当于胎动比平时减少一半。
    static func isSlow(durationSeconds: Int, baselineSeconds: Int?) -> Bool {
        guard let baselineSeconds else { return false }
        return durationSeconds > baselineSeconds * 2 && durationSeconds > slowFloorSeconds
    }

    static func latest(
        onDayOf now: Date, in sessions: [FetalMovementSession], calendar: Calendar = .current
    ) -> FetalMovementSession? {
        sessions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: now) }
            .max { $0.startedAt < $1.startedAt }
    }

    /// 最近 `days` 天（含今天），从早到晚。
    static func dailyTrend(
        _ sessions: [FetalMovementSession], days: Int = 14, now: Date, calendar: Calendar = .current
    ) -> [FetalMovementDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let sameDay = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
            let firstReached = sameDay
                .filter { $0.data.outcome == .reached }
                .min { $0.startedAt < $1.startedAt }
            return FetalMovementDay(
                date: day,
                reachedSeconds: firstReached?.data.durationSeconds,
                hadUnder: sameDay.contains { $0.data.outcome == .under })
        }
    }
}
```

- [ ] **Step 3: 跑测试**

Run: `… -only-testing:AimAppTests/FetalMovementModelsTests …`
Expected: 全部通过

- [ ] **Step 4: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): 胎动计数器与「和平时比」、每日趋势的统计"
```

---

### Task 5: FetalMovementStore

**Files:**
- Create: `apps/ios/AimApp/Features/FetalMovement/FetalMovementStore.swift`（161）
- Test: `apps/ios/AimApp/Tests/FetalMovementStoreTests.swift`（165）

**Interfaces:**
- Consumes：Task 4 全部类型；`BusinessRepositoryProtocol.fetchRecords(type:)`、`createRecord(draft:)`、`deleteRecord(recordID:)`。
- Produces（`@MainActor @Observable final class FetalMovementStore`）：
  - `init(defaults: UserDefaults = .standard, dedupeInterval: TimeInterval = FetalMovementCounter.defaultDedupeInterval)`
  - `var repository: BusinessRepositoryProtocol?`；`var clock: () -> Date`
  - `private(set) var sessions: [FetalMovementSession]`（新到旧）、`private(set) var active: FetalMovementCounter?`、`private(set) var unsaved: FetalMovementResult?`、`var errorMessage: String?`
  - `func load() async`、`func start()`、`func tap() -> FetalMovementCounter.TapResult`、`func finish() async -> FetalMovementCompletion?`、`@discardableResult func saveUnsaved() async -> Bool`、`func discardActive()`、`func delete(_ session: FetalMovementSession) async`
  - `var baselineSeconds: Int?`、`var today: FetalMovementSession?`
  - `struct FetalMovementCompletion: Equatable { let result: FetalMovementResult; let baselineSeconds: Int?; let saved: Bool; var isSlow: Bool }`

- [ ] **Step 1: 写失败的测试**

`Tests/FetalMovementStoreTests.swift`：

```swift
import XCTest
@testable import AimApp

@MainActor
final class FetalMovementStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "FetalMovementStoreTests-\(UUID().uuidString)")
    }

    private func makeStore(repository: FakeFetalRepository = FakeFetalRepository(), dedupe: TimeInterval = 3) -> FetalMovementStore {
        let store = FetalMovementStore(defaults: defaults, dedupeInterval: dedupe)
        store.repository = repository
        store.clock = { [unowned self] in self.now }
        return store
    }

    func testAnActiveCountSurvivesARelaunch() {
        let first = makeStore()
        first.start()
        now += 40
        _ = first.tap()

        let relaunched = makeStore()
        XCTAssertEqual(relaunched.active?.count, 1, "App 被系统杀掉后要从断点继续")
        XCTAssertEqual(relaunched.active?.startedAt, first.active?.startedAt)
    }

    func testFinishingSavesTheRecordAndReloads() async {
        let repository = FakeFetalRepository()
        let store = makeStore(repository: repository, dedupe: 0)
        store.start()
        for _ in 1...10 { now += 60; _ = store.tap() }

        let completion = await store.finish()

        XCTAssertEqual(completion?.result.outcome, .reached)
        XCTAssertEqual(completion?.saved, true)
        XCTAssertNil(store.active)
        XCTAssertNil(store.unsaved)
        XCTAssertEqual(repository.createdDrafts.first?.type, .fetalMovement)
        XCTAssertEqual(store.sessions.count, 1, "保存后重新拉取档案")
    }

    func testAFailedSaveKeepsTheResultForRetryAcrossRelaunch() async {
        let repository = FakeFetalRepository()
        repository.failCreates = true
        let store = makeStore(repository: repository)
        store.start()
        now += 30
        _ = store.tap()

        let completion = await store.finish()

        XCTAssertEqual(completion?.saved, false)
        XCTAssertNotNil(store.unsaved)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNotNil(makeStore(repository: repository).unsaved, "没保存上的结果不能丢")

        repository.failCreates = false
        let saved = await store.saveUnsaved()
        XCTAssertTrue(saved)
        XCTAssertNil(store.unsaved)
        XCTAssertNil(makeStore(repository: repository).unsaved)
    }

    func testBaselineIsCapturedBeforeTheNewSessionIsSaved() async {
        let repository = FakeFetalRepository()
        for seconds in [600, 620, 640] { repository.seed(seconds: seconds, at: now - 86_400) }
        let store = makeStore(repository: repository, dedupe: 0)
        await store.load()
        store.start()
        for _ in 1...10 { now += 200; _ = store.tap() }

        let completion = await store.finish()

        XCTAssertEqual(completion?.baselineSeconds, 620)
        XCTAssertEqual(completion?.isSlow, true, "2000 秒 > 620 × 2 且 > 30 分钟")
    }

    func testDiscardingAnEmptyCountLeavesNothingBehind() {
        let store = makeStore()
        store.start()
        store.discardActive()
        XCTAssertNil(store.active)
        XCTAssertNil(makeStore().active)
    }
}

/// 只实现胎动用到的三个接口；其余照抄 LibraryStoreTests 的 FakeLibraryRepository，
/// 一律 `throw APIError.notConfigured`（有默认实现的不必写）。
private final class FakeFetalRepository: BusinessRepositoryProtocol, @unchecked Sendable {
    var records: [RecordItem] = []
    var createdDrafts: [RecordDraft] = []
    var failCreates = false

    func seed(seconds: Int, at date: Date) {
        records.append(item(FetalMovementResult(
            startedAt: date, durationSeconds: seconds, count: 10, outcome: .reached,
            taps: Array(repeating: 0, count: 10)).draft))
    }

    private func item(_ draft: RecordDraft) -> RecordItem {
        RecordItem(
            id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
            type: draft.type, occurredAt: draft.occurredAt, visibility: draft.visibility,
            title: draft.title, content: draft.content, structuredData: draft.structuredData,
            attachmentRefs: [], createdAt: .now, updatedAt: .now)
    }

    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot {
        RecordSnapshot(records: records.filter { type == nil || $0.type == type })
    }

    func createRecord(draft: RecordDraft) async throws -> RecordItem {
        if failCreates { throw APIError.invalidResponse }
        createdDrafts.append(draft)
        let created = item(draft)
        records.append(created)
        return created
    }

    func deleteRecord(recordID: UUID) async throws { records.removeAll { $0.id == recordID } }

    // 以下照抄 Tests/LibraryStoreTests.swift 里 FakeLibraryRepository 的其余必需方法，
    // 全部 throw APIError.notConfigured（返回 Void 的写成空实现）。
}
```

（`RecordItem` 初始化参数以 `LibraryStoreTests.swift:17-26` 的写法为准。照抄其余协议方法时逐个对照 `BusinessRepositoryProtocol`，编译器会指出缺哪个。）

登记编号 165（测试 target）。Run: `… -only-testing:AimAppTests/FetalMovementStoreTests …` Expected: 编译失败。

- [ ] **Step 2: 实现**

`Features/FetalMovement/FetalMovementStore.swift`（登记 161）：

```swift
import Foundation
import Observation

struct FetalMovementCompletion: Equatable, Sendable {
    let result: FetalMovementResult
    /// 这次之前的「平时」——必须在保存前取，否则这次会把自己算进平时里。
    let baselineSeconds: Int?
    let saved: Bool

    var isSlow: Bool {
        result.outcome == .reached
            && FetalMovementInsights.isSlow(durationSeconds: result.durationSeconds, baselineSeconds: baselineSeconds)
    }
}

/// 胎动计数的状态：进行中的计数（本地断点）、没保存上的结果、档案里的历史。
///
/// 进行中的计数与未保存的结果都写进 UserDefaults——计数可能持续两小时，
/// 中途被系统回收是常态，丢掉就等于让孕妈重数一遍。
@MainActor
@Observable
final class FetalMovementStore {
    var repository: BusinessRepositoryProtocol?
    var clock: () -> Date = { Date() }
    private(set) var sessions: [FetalMovementSession] = []
    private(set) var active: FetalMovementCounter?
    private(set) var unsaved: FetalMovementResult?
    var errorMessage: String?

    let dedupeInterval: TimeInterval
    private let defaults: UserDefaults

    private enum Keys {
        static let active = "aim.fetalMovement.active"
        static let unsaved = "aim.fetalMovement.unsaved"
    }

    init(defaults: UserDefaults = .standard,
         dedupeInterval: TimeInterval = FetalMovementCounter.defaultDedupeInterval) {
        self.defaults = defaults
        self.dedupeInterval = dedupeInterval
        active = Self.read(FetalMovementCounter.self, key: Keys.active, from: defaults)
        unsaved = Self.read(FetalMovementResult.self, key: Keys.unsaved, from: defaults)
    }

    var baselineSeconds: Int? { FetalMovementInsights.baselineSeconds(sessions) }
    var today: FetalMovementSession? { FetalMovementInsights.latest(onDayOf: clock(), in: sessions) }

    func load() async {
        guard let repository else { return }
        do {
            let snapshot = try await repository.fetchRecords(type: .fetalMovement)
            sessions = snapshot.records
                .compactMap(FetalMovementSession.init(record:))
                .sorted { $0.startedAt > $1.startedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start() {
        guard active == nil else { return }
        active = FetalMovementCounter(startedAt: clock(), dedupeInterval: dedupeInterval)
        persist()
    }

    func tap() -> FetalMovementCounter.TapResult {
        guard var counter = active else { return .ignored }
        let result = counter.tap(at: clock())
        active = counter
        persist()
        return result
    }

    func finish() async -> FetalMovementCompletion? {
        guard let counter = active else { return nil }
        let baseline = baselineSeconds
        let result = counter.result(at: clock())
        active = nil
        unsaved = result
        persist()
        let saved = await saveUnsaved()
        return FetalMovementCompletion(result: result, baselineSeconds: baseline, saved: saved)
    }

    @discardableResult
    func saveUnsaved() async -> Bool {
        guard let result = unsaved, let repository else { return false }
        do {
            _ = try await repository.createRecord(draft: result.draft)
            unsaved = nil
            errorMessage = nil
            persist()
            await load()
            return true
        } catch {
            errorMessage = "没保存上，重试"
            return false
        }
    }

    func discardActive() {
        active = nil
        persist()
    }

    func delete(_ session: FetalMovementSession) async {
        guard let repository else { return }
        do {
            try await repository.deleteRecord(recordID: session.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persist() {
        Self.write(active, key: Keys.active, to: defaults)
        Self.write(unsaved, key: Keys.unsaved, to: defaults)
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

- [ ] **Step 3: 跑测试**

Run: `… -only-testing:AimAppTests/FetalMovementStoreTests …`，再跑完整 `AimAppTests`
Expected: 全部通过

- [ ] **Step 4: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): 胎动计数的本地断点、保存与重试"
```

---

### Task 6: 计数页与胎动页

**Files:**
- Create: `apps/ios/AimApp/Features/FetalMovement/FetalMovementCounterView.swift`（162）
- Create: `apps/ios/AimApp/Features/FetalMovement/FetalMovementView.swift`（163）

**Interfaces:**
- Consumes：`FetalMovementStore`（通过 `@Environment(FetalMovementStore.self)` 取得）、Task 4 模型、`AgentStore.prepareAnalysis(_:context:)`、`AgentView(store:onClose:)`、`AimCircleButton`、`.aimCard()`、`AimMetrics`、颜色 `Color.aim*`。
- Produces：
  - `struct FetalMovementCounterView: View { let agentStore: AgentStore; let onClose: () -> Void }`
  - `struct FetalMovementView: View { let agentStore: AgentStore }`（胎动页，可被 push）
  - `struct FetalMovementHomeCard: View { let agentStore: AgentStore }`（首页卡）
  - 无障碍标识：`fetal-movement-tap`、`fetal-movement-count`、`fetal-movement-end`、`fetal-movement-finished`、`fetal-movement-done`、`fetal-movement-safety`、`fetal-movement-less-than-usual`、`fetal-movement-guide`、`fetal-movement-page`、`fetal-movement-start`、`fetal-movement-retry`、`home-fetal-movement-card`、`home-fetal-movement-start`

- [ ] **Step 1: 计数页**

`FetalMovementCounterView.swift`（登记 162）：

```swift
import SwiftUI

/// 胎动相关的固定文案集中放在这里，便于医学审核一次看全。
enum FetalMovementCopy {
    static let howTo = "选宝宝活跃的时段（饭后、睡前），侧躺或坐着。一阵连续的动只按一次，数到 10 次就结束。"
    static let underRule = "2 小时内不足 10 次，或比平时明显少了，要尽快联系医院。"
    static let mostImportant = "感觉胎动明显变少、变弱或停止时，不用数完，立即联系医院或去产科急诊。"
    static let doctorFirst = "如果你的医生教过别的数法，以医生为准。"
    static let underTitle = "2 小时内胎动不足 10 次"
    static let underBody = "请现在联系你的产检医院，或去产科急诊。不要等到明天，也不要靠喝冷水、吃甜食来「叫醒」宝宝。"
    static let lessTitle = "感觉胎动明显少了"
    static let lessBody = "不用数完。请现在联系你的产检医院，或去产科急诊。"
    static let recordedNote = "已记录。数够 10 次不代表一切正常，感觉不对就联系医院。"

    static func slow(duration: Int, baseline: Int) -> String {
        "这次用了 \(FetalMovementFormat.duration(duration))，比你平时（约 \(FetalMovementFormat.duration(baseline))）慢了一倍多，胎动可能比平时少。建议尽快联系你的产检医院。"
    }
}

struct FetalMovementCounterView: View {
    @Environment(FetalMovementStore.self) private var store
    let agentStore: AgentStore
    let onClose: () -> Void

    private enum Phase: Equatable {
        case counting
        case finished(FetalMovementCompletion)
        case safety(title: String, body: String)
    }

    @State private var phase: Phase = .counting
    @State private var tapCount = 0
    @State private var ignoredCount = 0
    @State private var confirmingEnd = false
    @State private var showingGuide = false
    @State private var showingAgent = false

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .counting: counting
                case let .finished(completion): finished(completion)
                case let .safety(title, body): safety(title: title, body: body)
                }
            }
            .padding(.horizontal, AimMetrics.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.aimCanvas)
            .navigationTitle("数胎动")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if phase != .counting { Button("关闭", action: onClose) }
                }
            }
        }
        .onAppear { store.start() }
        .sheet(isPresented: $showingGuide) { FetalMovementGuideView() }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
        .confirmationDialog("现在结束吗？这次会记为未数完。", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("结束并记录") { Task { await end() } }
            Button("继续数", role: .cancel) {}
        }
    }

    private var counting: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            let counter = store.active
            VStack(spacing: AimMetrics.space16) {
                Button {
                    phase = .safety(title: FetalMovementCopy.lessTitle, body: FetalMovementCopy.lessBody)
                } label: {
                    Label("胎动明显少了？", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.aimDanger)
                }
                .accessibilityIdentifier("fetal-movement-less-than-usual")

                Text(Self.clock(counter?.elapsed(at: context.date) ?? 0))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.aimTextPrimary)
                Text("目标 10 次").font(.subheadline).foregroundStyle(Color.aimTextSecondary)

                Button { tap() } label: {
                    VStack(spacing: AimMetrics.space4) {
                        Text("\(counter?.count ?? 0)")
                            .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                            .accessibilityIdentifier("fetal-movement-count")
                        Text("动了一下").font(.headline)
                    }
                    .foregroundStyle(Color.aimTextOnAccent)
                    .frame(width: 220, height: 220)
                    .background(Color.aimAccent, in: Circle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .medium), trigger: tapCount)
                .sensoryFeedback(.impact(weight: .light), trigger: ignoredCount)
                .accessibilityIdentifier("fetal-movement-tap")

                if ignoredCount > 0 {
                    Text("这阵已经记过了").font(.caption).foregroundStyle(Color.aimTextSecondary)
                }

                VStack(alignment: .leading, spacing: AimMetrics.space8) {
                    Text(FetalMovementCopy.howTo)
                    Text(FetalMovementCopy.underRule)
                    Text(FetalMovementCopy.mostImportant).foregroundStyle(Color.aimDanger)
                }
                .font(.footnote)
                .foregroundStyle(Color.aimTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .aimCard()

                HStack {
                    Button("怎么数？") { showingGuide = true }
                        .accessibilityIdentifier("fetal-movement-guide")
                    Spacer()
                    Button("结束") {
                        if (store.active?.count ?? 0) == 0 { store.discardActive(); onClose() }
                        else { confirmingEnd = true }
                    }
                    .accessibilityIdentifier("fetal-movement-end")
                }
                .font(.subheadline)
            }
            .onChange(of: context.date) { _, now in
                // 前台计时只负责刷新显示；满 2 小时的判断以开始时间为准，
                // 从后台回来时第一次刷新就会结束。
                if store.active?.isExpired(at: now) == true { Task { await end() } }
            }
        }
    }

    private func tap() {
        switch store.tap() {
        case .counted: tapCount += 1; ignoredCount = 0
        case .ignored: ignoredCount += 1
        case .reachedTarget: tapCount += 1; Task { await end() }
        case .expired: Task { await end() }
        }
    }

    private func end() async {
        guard let completion = await store.finish() else { return }
        if completion.result.outcome == .under {
            phase = .safety(title: FetalMovementCopy.underTitle, body: FetalMovementCopy.underBody)
        } else {
            phase = .finished(completion)
        }
    }

    private func finished(_ completion: FetalMovementCompletion) -> some View {
        VStack(alignment: .leading, spacing: AimMetrics.space16) {
            Text(completion.result.outcome == .reached
                 ? "\(completion.result.count) 次，用了 \(FetalMovementFormat.duration(completion.result.durationSeconds))"
                 : "\(completion.result.count) 次 · 未数完")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.aimTextPrimary)
            if completion.isSlow, let baseline = completion.baselineSeconds {
                Text(FetalMovementCopy.slow(duration: completion.result.durationSeconds, baseline: baseline))
                    .font(.subheadline)
                    .foregroundStyle(Color.aimAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .aimCard()
                askAgentButton("我数胎动用了 \(FetalMovementFormat.duration(completion.result.durationSeconds))，比平时慢了一倍多，现在该怎么办？")
            }
            Text(FetalMovementCopy.recordedNote).font(.footnote).foregroundStyle(Color.aimTextSecondary)
            if !completion.saved { retryButton }
            Button("完成", action: onClose)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("fetal-movement-done")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fetal-movement-finished")
    }

    private func safety(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: AimMetrics.space16) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.aimDanger)
            Text(body).font(.body).foregroundStyle(Color.aimTextPrimary)
            askAgentButton("我感觉胎动比平时少了，现在该怎么办？")
            if store.unsaved != nil { retryButton }
            Button("我知道了", action: onClose).buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.aimDangerSoft, in: RoundedRectangle(cornerRadius: AimMetrics.radiusCard))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fetal-movement-safety")
    }

    private var retryButton: some View {
        Button("没保存上，重试") { Task { await store.saveUnsaved() } }
            .accessibilityIdentifier("fetal-movement-retry")
    }

    private func askAgentButton(_ question: String) -> some View {
        Button {
            agentStore.prepareAnalysis(question, context: AgentContext(title: "胎动", summary: "刚刚数胎动"))
            showingAgent = true
        } label: {
            Label("问问 AIM", systemImage: "wand.and.sparkles")
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// 计数页内置的说明。详细内容在资料库「孕期百科 · 胎动与数胎动」。
struct FetalMovementGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("怎么数") { Text(FetalMovementCopy.howTo) }
                Section("什么时候联系医院") {
                    Text(FetalMovementCopy.underRule)
                    Text(FetalMovementCopy.mostImportant).foregroundStyle(Color.aimDanger)
                }
                Section { Text(FetalMovementCopy.doctorFirst) }
                Section { Text("更多说明见资料库 · 孕期百科「胎动与数胎动」。").font(.footnote) }
            }
            .navigationTitle("怎么数胎动")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("好") { dismiss() } } }
        }
    }
}
```

（颜色、间距常量以 `Core/DesignSystem/AimTheme.swift` / `AimMetrics.swift` 实际存在的为准；`Color.aimDangerSoft`、`AimMetrics.radiusCard` 在资料库代码里已用过。）

- [ ] **Step 2: 胎动页与首页卡**

`FetalMovementView.swift`（登记 163）：

```swift
import SwiftUI

/// 胎动页：今天、最近 14 天趋势、历史。
struct FetalMovementView: View {
    @Environment(FetalMovementStore.self) private var store
    let agentStore: AgentStore

    @State private var counting = false
    @State private var showingAgent = false
    @State private var showingGuide = false

    var body: some View {
        List {
            Section {
                todayRow
                Button { counting = true } label: {
                    Label("开始数胎动", systemImage: "hand.tap")
                }
                .accessibilityIdentifier("fetal-movement-start")
                Button("怎么数？") { showingGuide = true }
                    .accessibilityIdentifier("fetal-movement-guide")
                if store.unsaved != nil {
                    Button("有一次没保存上，重试") { Task { await store.saveUnsaved() } }
                        .accessibilityIdentifier("fetal-movement-retry")
                }
            }
            Section("最近 14 天 · 数到 10 次的用时") {
                FetalMovementTrendBars(days: FetalMovementInsights.dailyTrend(store.sessions, now: store.clock()))
            }
            ForEach(groupedByDay, id: \.day) { group in
                Section(group.day.formatted(.dateTime.month().day().weekday())) {
                    ForEach(group.sessions) { session in
                        HStack {
                            Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(Color.aimTextSecondary)
                            Text(FetalMovementFormat.summary(session.data))
                                .foregroundStyle(session.data.outcome == .under ? Color.aimDanger : Color.aimTextPrimary)
                        }
                        .swipeActions {
                            Button(role: .destructive) { Task { await store.delete(session) } } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            Section {
                Text(FetalMovementCopy.mostImportant).font(.footnote).foregroundStyle(Color.aimDanger)
            }
        }
        .navigationTitle("胎动")
        .accessibilityIdentifier("fetal-movement-page")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    agentStore.prepareAnalysis("帮我看看最近的胎动记录", context: AgentContext(title: "胎动", summary: recentSummary))
                    showingAgent = true
                } label: { Image(systemName: "wand.and.sparkles") }
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        .fullScreenCover(isPresented: $counting) {
            FetalMovementCounterView(agentStore: agentStore) { counting = false }
        }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
        .sheet(isPresented: $showingGuide) { FetalMovementGuideView() }
    }

    private var todayRow: some View {
        Text(store.today.map { "今天 " + FetalMovementFormat.summary($0.data) } ?? "今天还没数")
            .font(.headline)
    }

    private var recentSummary: String {
        let week = store.sessions.prefix(7).map {
            $0.startedAt.formatted(date: .abbreviated, time: .shortened) + " " + FetalMovementFormat.summary($0.data)
        }
        return week.isEmpty ? "还没有胎动记录" : "最近的胎动记录：\n" + week.joined(separator: "\n")
    }

    private var groupedByDay: [(day: Date, sessions: [FetalMovementSession])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: store.sessions) { calendar.startOfDay(for: $0.startedAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }
}

/// 14 根柱子：高度是当天第一次数到 10 次的用时；当天有「不足 10 次」的标红点。
struct FetalMovementTrendBars: View {
    let days: [FetalMovementDay]

    var body: some View {
        let longest = max(days.compactMap(\.reachedSeconds).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(days, id: \.date) { day in
                VStack(spacing: 2) {
                    if day.hadUnder { Circle().fill(Color.aimDanger).frame(width: 6, height: 6) }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(day.reachedSeconds == nil ? Color.aimSurfaceSunken : Color.aimAccent)
                        .frame(height: day.reachedSeconds.map { 8 + CGFloat($0) / CGFloat(longest) * 60 } ?? 4)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 80, alignment: .bottom)
        .accessibilityLabel("最近 14 天数胎动用时")
    }
}

/// 首页「数胎动」卡。孕 28 周起由首页决定是否显示。
struct FetalMovementHomeCard: View {
    @Environment(FetalMovementStore.self) private var store
    let agentStore: AgentStore
    @State private var counting = false

    var body: some View {
        // 「开始」不能放进 NavigationLink 的 label 里——链接会吞掉内层按钮的点击。
        HStack {
            NavigationLink {
                FetalMovementView(agentStore: agentStore)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: AimMetrics.space4) {
                        Text("数胎动").font(.headline).foregroundStyle(Color.aimTextPrimary)
                        Text(store.today.map { "今天 " + FetalMovementFormat.summary($0.data) } ?? "今天还没数")
                            .font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-fetal-movement-card")
            Button("开始") { counting = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("home-fetal-movement-start")
        }
        .aimCard()
        .task { await store.load() }
        .fullScreenCover(isPresented: $counting) {
            FetalMovementCounterView(agentStore: agentStore) { counting = false }
        }
    }
}
```

- [ ] **Step 3: 编译**

登记 162、163。Run: `make ios-build 2>&1 | grep -E "error:|BUILD" | tail -5`（Makefile 默认目标无需模拟器）
Expected: `** BUILD SUCCEEDED **`（此时还没有任何入口使用这些视图，属正常）

- [ ] **Step 4: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): 胎动计数页、安全提示页与胎动页"
```

---

### Task 7: 入口接入与 UI 用例

**Files:**
- Modify: `apps/ios/AimApp/App/AimApp.swift`（:36-47 store 声明、`body` 的 `.environment(...)`、`reloadRepositories()` :146-160）
- Modify: `apps/ios/AimApp/Features/Home/HomeDashboardView.swift:33-39`
- Modify: `apps/ios/AimApp/Features/Library/LibraryCatalog.swift`（`LibraryCategoryID` :26、`title` :38、`icon` :50、`summary(from:)` :79、`LibraryCatalog.categories` :213）
- Modify: `apps/ios/AimApp/Features/Library/LibraryView.swift:40` 附近网格
- Modify: `apps/ios/AimApp/Features/Library/LibraryCategoryDetail.swift`（body switch :21、`addHint` :476）
- Modify: `apps/ios/AimApp/Features/Library/EncyclopediaEntryView.swift`（footer 之前）
- Test: `apps/ios/AimApp/UITests/CoreJourneyUITests.swift`

**Interfaces:**
- Consumes：Task 5 `FetalMovementStore`；Task 6 `FetalMovementView`、`FetalMovementHomeCard`、`FetalMovementCounterView`。
- Produces：`LibraryCategoryID.fetalMovement`；启动参数 `-fetal-dedupe-zero`。

- [ ] **Step 1: 写失败的 UI 用例**

先把 `completePregnancySetup(in:)` 改为可选天数（默认值保持 154 = 孕 18 周，不影响既有用例）：

```swift
    private func completePregnancySetup(in app: XCUIApplication, daysUntilDue: Int = 154) {
```

函数体里 `.date(byAdding: .day, value: 154, to: Date())` 改为 `value: daysUntilDue`。

新增用例：

```swift
    /// 孕 28 周起首页有「数胎动」：数到 10 次后看到完成页，首页显示今天的结果。
    func testCountingFetalMovementFromHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session", "-fetal-dedupe-zero"]
        app.launch()

        registerNewAccount(in: app)
        // 距预产期 70 天 ≈ 孕 30 周。
        completePregnancySetup(in: app, daysUntilDue: 70)

        let start = app.buttons["home-fetal-movement-start"]
        reveal(start, in: app)
        start.tap()

        let tap = app.buttons["fetal-movement-tap"]
        XCTAssertTrue(tap.waitForExistence(timeout: 10))
        for _ in 1...10 { tap.tap() }

        XCTAssertTrue(app.otherElements["fetal-movement-finished"].waitForExistence(timeout: 10),
                      "数到 10 次应当自动结束并显示完成页")
        app.buttons["fetal-movement-done"].tap()

        let card = app.buttons["home-fetal-movement-card"]
        reveal(card, in: app)
        XCTAssertTrue(card.label.contains("10 次") || app.staticTexts["今天 10 次 · 不到 1 分钟"].exists,
                      "首页卡应当显示今天这次的结果")
    }
```

Run: `xcodebuild … test -only-testing:AimAppUITests/CoreJourneyUITests/testCountingFetalMovementFromHome`
Expected: FAIL（首页没有胎动卡）

- [ ] **Step 2: App 注入 store**

`AimApp.swift`：
- 声明处加：

```swift
    /// UI 测试要在一秒内连点 10 次，用启动参数关掉防误触去重。
    @State private var fetalMovementStore = FetalMovementStore(
        dedupeInterval: ProcessInfo.processInfo.arguments.contains("-fetal-dedupe-zero")
            ? 0 : FetalMovementCounter.defaultDedupeInterval)
```

- `TabView` 上 `.environment(agentDestinations)` 之后加 `.environment(fetalMovementStore)`。
- `reloadRepositories()` 里 `libraryStore.repository = repository` 之后加 `fetalMovementStore.repository = repository`，并在加载序列末尾加 `await fetalMovementStore.load()`。
- 若 `-reset-session` 会清理会话数据，确认它不影响胎动断点（断点按设备保存是对的）；但为让 UI 用例从干净状态开始，在 `-reset-session` 时同样清掉 `aim.fetalMovement.active` 与 `aim.fetalMovement.unsaved`（在 `AppSessionStore.swift:38` 的 `clear()` 分支旁加两行 `UserDefaults.standard.removeObject(forKey:)`）。

- [ ] **Step 3: 首页卡**

`HomeDashboardView.swift` 的区块顺序里 `todayCard` 之后加：

```swift
                    if (store.pregnancy?.weeks ?? 0) >= 28 {
                        FetalMovementHomeCard(agentStore: agentStore)
                    }
```

（`HomeDashboardView` 已持有 `agentStore`；若属性名不同按实际调整。）

- [ ] **Step 4: 资料库卡**

`LibraryCatalog.swift`：
- `LibraryCategoryID` 加 `case fetalMovement`；`title` → `"胎动"`；`icon` → `"hand.tap"`。
- `summary(from:)` 加：

```swift
        case .fetalMovement:
            let latest = snapshot.records
                .compactMap(FetalMovementSession.init(record:))
                .max { $0.startedAt < $1.startedAt }
            guard let latest else { return LibrarySummary(headline: "28 周起每天数一数") }
            return LibrarySummary(headline: FetalMovementFormat.summary(latest.data))
```

- `LibraryCatalog.categories` 在 `.questions` 之后插入 `LibraryCategory(id: .fetalMovement, isBanner: false)`。
- `placeholderHeadline` 有 default，不必改。

`LibraryView.swift` 网格的 `ForEach(LibraryCatalog.gridCategories)` 改为 `ForEach(visibleGridCategories)`，并加：

```swift
    /// 胎动卡 28 周起显示；更早但已经有胎动记录的（比如改过预产期）也显示。
    private var visibleGridCategories: [LibraryCategory] {
        LibraryCatalog.gridCategories.filter { category in
            guard category.id == .fetalMovement else { return true }
            return (store.currentWeek ?? 0) >= 28
                || store.snapshot.records.contains { $0.type == .fetalMovement }
        }
    }
```

`LibraryCategoryDetail.swift`：body 的 switch 加 `case .fetalMovement: FetalMovementView(agentStore: agentStore)`（若 `agentStore` 是可选，用 `if let` 包一层，否则显示 `comingSoon`）；`addHint` 加 `case .fetalMovement: "「最近胎动正常吗」"`。

- [ ] **Step 5: 百科条目按钮**

`EncyclopediaEntryView.swift`：加 `@State private var countingFetalMovement = false`；在 footer 文本之前加：

```swift
                if entry.id == "body.fetal-movement" {
                    Button { countingFetalMovement = true } label: {
                        Label("开始数胎动", systemImage: "hand.tap")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("encyclopedia-start-fetal-movement")
                }
```

并在 body 已有的 `.fullScreenCover` 旁加：

```swift
        .fullScreenCover(isPresented: $countingFetalMovement) {
            FetalMovementCounterView(agentStore: agentStore) { countingFetalMovement = false }
        }
```

- [ ] **Step 6: 跑测试**

Run:
1. `make ios-build` → BUILD SUCCEEDED
2. 单元测试 `-only-testing:AimAppTests` → 0 失败
3. UI：`-only-testing:AimAppUITests/CoreJourneyUITests/testCountingFetalMovementFromHome` → passed
4. UI 回归（资料库网格多了一张卡，可能把元素挤到下面）：`testEncyclopediaTopicEntryAndAskAIM`、`testBuiltInReferenceItemsOpenTheirDetail` → passed

前提：本地 `make dev` 栈在跑，且 API 镜像含 Task 1 的改动（若不含，`docker compose --env-file .env --profile local -f infrastructure/compose/compose.yaml up -d --build api` 重建 API）。

- [ ] **Step 7: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): 首页、资料库与百科条目接入胎动计数"
```
