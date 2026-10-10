# 资料库 2.0 第 3 期：档案可编辑与产检报告闭环 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 家人能编辑档案；产检报告有结构（更多指标、其他化验项、可选文字、照片）；拍报告给 AIM 后，AIM 识别并给出预览卡，确认后一次建好报告与「想问医生」；报告详情可对比上次、标出异常；本周关注提示最近报告的异常项。

**Architecture:** 后端 records 放宽 checkup 校验、修 PATCH、放开家庭可见记录的编辑权限；agent_access 新增审批类工具 `create-checkup-report`，一个事务建报告与问题，结果带 `record_ids` 供整批撤销。web 新增报告预览卡。iOS：模型与 DTO 扩展、撤销解析修复、报告表单（全部指标 + 其他化验项 + 照片上传）、报告详情、本周关注新规则、UI 测试密码弹窗。

**Tech Stack:** FastAPI + pytest；Eve agent；React + vitest；SwiftUI + XCTest。

规格：`docs/superpowers/specs/2026-10-09-library-2-design.md` §5.1、§5.2、§5.4、§6.3、§7.3、§11。

## Global Constraints

- 所有面向用户的文字、注释、提交信息用简体中文。
- 编辑权限：家庭可见的记录家里任何成员都能改；仅自己可见的只有作者能改（删除权限同编辑）。
- checkup：`hospital`、`exam_items`、`result`、`doctor_advice` 均可选（可缺省或为字符串）；`metrics` 白名单新增 `fetal_heart_rate`（100–200）、`fundal_height_cm`（10–45），原有 `weight_kg (30,200)`、`systolic (60,250)`、`diastolic (30,150)`、`fasting_glucose (2,20)`、`hemoglobin (50,200)` 不变；新增 `other_items[]`（≤60 项），每项 `name`（必填，≤40 字）、`value`（必填字符串，≤40 字）、`unit`（≤20）、`reference`（≤60）、`flag ∈ {high, low, abnormal, null}`。
- 照片：每条记录 ≤4 张（后端上限）。
- `create_checkup_report`：执行前确认（`approval: always()`，不在 `DIRECT_EXECUTION_TOOLS`）；参数 `date`、`hospital?`、`metrics?`、`other_items?`、`attachment_ids`（≤4）、`result?`、`doctor_advice?`、`follow_up_questions?`（≤5，每条 ≤60 字）；一个事务内建 checkup 与 question（`structured_data.report_id` 指回报告）；返回 `{record_id, record_ids, title, question_count}`；撤销整批删除。
- 读图规则：看不清的值不填、不猜；`flag` 只按报告单标记或参考范围判断，不做医学解读；异常项的追问写成问题而不是结论。
- 本周关注新规则（优先级在血压之后、反复症状之前）：最近 30 天内最新一份报告有 flag 非空项目、且尚未全部加入「想问医生」→「最近报告有 N 项异常，记得问医生」（info 级）。
- 测试：API `PYTHONPATH=src python3 -m pytest`；Agent `make -C services/agent test`；web `npm test --prefix apps/agent-web` + build；iOS 用 iPhone 18 Pro。只可重建 api、eve 容器。

---

### Task 1: UI 测试不再被系统密码弹窗挡住

**Files:**
- Modify: `apps/ios/AimApp/Features/Onboarding/OnboardingView.swift:42-44`
- Modify: 一个放启动参数判断的地方（若已有类似 `AppLaunchFlags`/`ProcessInfo` 封装则复用；否则在 `App/AppSessionStore.swift` 附近加 `enum LaunchFlags { static var isUITesting: Bool }`）

- [ ] **Step 1**：`LaunchFlags.isUITesting = ProcessInfo.processInfo.arguments.contains("-reset-session") || …contains("-ui-testing")`（UI 测试都以 `-reset-session` 启动）。
- [ ] **Step 2**：密码框 `.textContentType(LaunchFlags.isUITesting ? nil : (register ? .newPassword : .password))`；`AccountSection.swift:104-105` 同样处理。
- [ ] **Step 3**：跑 `testEncyclopediaTopicEntryAndAskAIM`（会走注册）确认不被弹窗挡；单元测试全过。
- [ ] **Step 4**：提交 `test(ios): UI 测试下密码框不触发系统强密码与保存密码弹窗`。

---

### Task 2: 后端档案编辑与报告结构

**Files:**
- Modify: `services/api/src/aim_api/contexts/records/application/commands/update_record.py:49`（传 title）
- Modify: `services/api/src/aim_api/contexts/records/domain/record.py`（`assert_can_mutate` 改为接收可见性规则；checkup 校验）
- Modify: `delete_record` 命令的权限判断（与编辑一致）
- Test: `services/api/tests/domain/records/`（checkup 新校验）、`services/api/tests/integration/records/test_records_api.py`（编辑权限、知识条目 PATCH）

**Interfaces:**
- Produces：`Record.assert_can_mutate(account_id: UUID)`：`visibility == family` 时任何家庭成员可改（成员资格已由命令层校验），`private` 时只有作者；checkup 新字段与校验。

- [ ] **Step 1: 测试（先失败）**
  - 领域：checkup 只给 `metrics={"fetal_heart_rate": 145}` 合法；`fundal_height_cm=9` 被拒；`other_items` 缺 `name`、`value` 非字符串、61 项、`flag="weird"` 都被拒；四段文字缺省合法、给非字符串被拒。
  - 集成：家人 B 可以 PATCH 家人 A 的 family 记录（200）；B PATCH A 的 private 记录 404 或 403（以现有可见性：private 对 B 不可见 → 404）；知识条目 PATCH 改标题成功（修 title 漏传）；B 可以删除 A 的 family 记录。
- [ ] **Step 2: 实现**
  - `update_record.py:49` → `Record._validate_payload(record.record_type, record.structured_data, record.content, record.title)`。
  - `assert_can_mutate`：

```python
    def assert_can_mutate(self, account_id: UUID) -> None:
        # 家庭可见的记录属于整个家庭，家里任何成员都能改（成员资格由命令层先校验）；
        # 仅自己可见的只有作者能改。
        if self.visibility is RecordVisibility.family:
            return
        if self.author_account_id != account_id:
            raise RecordAccessDenied("only the record author can mutate a private record")
```

  - checkup 分支：

```python
        if record_type is RecordType.checkup:
            for field in ("hospital", "exam_items", "result", "doctor_advice"):
                value = structured_data.get(field)
                if value is not None and not isinstance(value, str):
                    raise RecordValidationError(f"checkup {field} must be a string")
            cls._validate_checkup_metrics(structured_data.get("metrics"))
            cls._validate_other_items(structured_data.get("other_items"))
            return
```

    `CHECKUP_METRIC_RANGES` 加 `"fetal_heart_rate": (100, 200)`、`"fundal_height_cm": (10, 45)`；`OTHER_ITEM_FLAGS: ClassVar[frozenset[str]] = frozenset({"high", "low", "abnormal"})`；`MAX_OTHER_ITEMS: ClassVar[int] = 60`；`_validate_other_items`：None 放行；非 list 报错；>60 报错；每项为 dict，`name`、`value` 为非空字符串且各 ≤40；`unit` ≤20、`reference` ≤60（可缺省或 None）；`flag` 为 None 或在集合内；不允许其他键。
  - 注意 agent 侧 `create_record.ts` 现在给 checkup 补空串（`hospital: input.hospital ?? ""`），保持兼容即可。
- [ ] **Step 3**：API 全量、`make contracts`（若有变化一并提交）。提交 `feat(api): 家人可编辑家庭记录；产检报告支持更多指标与其他化验项`。

---

### Task 3: create_checkup_report 工具与整批撤销

**Files:**
- Modify: `services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/router.py`（请求模型、`_create_checkup_report`、路由 `write=True`）
- Modify: `services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/operation_undo.py`（`create_checkup_report` 进删除记录组；支持 `record_ids`）
- Modify: `services/api/src/aim_api/contexts/records/application/commands/create_record.py`（如需支持同一事务建多条，新增 `create_records_in_one_transaction` 或在 handler 中复用 uow 不提交——以现有 UoW 能力为准）
- Create: `services/agent/agent/tools/create_checkup_report.ts`
- Modify: `services/agent/agent/instructions.md`、`services/agent/tests/runtime-gate.test.ts`、`apps/agent-web/src/tools/labels.ts`（`TOOL_TITLES.create_checkup_report = "记一份产检报告"`）
- Test: `services/api/tests/integration/agent_access/test_checkup_report_tool.py`、Agent 侧 approval 断言

**Interfaces:**
- Produces：`POST /internal/agent-tools/create-checkup-report`，body 字段见 Global Constraints + `approved: bool`；未 approved → approval_required；成功 data：`{"record_id": <报告 id>, "record_ids": [报告, 问题…], "title": "<M月d日> 产检报告", "question_count": n}`。

- [ ] **Step 1: 测试（先失败）**：未 approved 返回 approval_required；approved 时一次建 1 条 checkup + n 条 question（`structured_data.report_id` 等于报告 id，`answered=false`）、照片挂到报告上；`other_items` 非法时整批都不写（事务回滚，question 也不存在）；`follow_up_questions` 6 条被 422 拒；`undo_operation` 撤销后报告与问题都被删除；撤销旧的单条 `record_id` 结果仍然有效（向后兼容）。
- [ ] **Step 2: 实现**
  - 请求模型：

```python
class OtherItem(BaseModel):
    name: str = Field(min_length=1, max_length=40)
    value: str = Field(min_length=1, max_length=40)
    unit: str | None = Field(default=None, max_length=20)
    reference: str | None = Field(default=None, max_length=60)
    flag: Literal["high", "low", "abnormal"] | None = None


class CreateCheckupReportRequest(BaseModel):
    date: date
    hospital: str | None = Field(default=None, max_length=100)
    metrics: dict[str, float] | None = None
    other_items: list[OtherItem] = Field(default_factory=list, max_length=60)
    attachment_ids: list[UUID] = Field(default_factory=list, max_length=4)
    result: str | None = Field(default=None, max_length=500)
    doctor_advice: str | None = Field(default=None, max_length=500)
    follow_up_questions: list[Annotated[str, Field(min_length=1, max_length=60)]] = Field(
        default_factory=list, max_length=5
    )
    approved: bool = False
```

  - `_create_checkup_report`：在同一个 session 里先建报告（`occurred_at = date 当天 09:00 Asia/Shanghai 转 UTC`、`visibility=family`、`title="M月d日 产检报告"`、`structured_data` 只放非空字段 + `metrics` + `other_items`、`attachment_ids`），再逐条建 question（`content=问题`、`structured_data={"answered": False, "report_id": str(report_id)}`、`visibility=family`）；**只在最后提交一次**（若 `create_record.execute` 内部自行 commit，则新增一个不提交的变体或直接用 repository + 校验函数，确保失败时整批回滚）。返回 data 见 Interfaces；summary「已记下 10月3日产检报告，并攒了 n 个想问医生的问题」。
  - question 领域校验需接受 `report_id`（字符串 uuid，可选）——在 question 分支加校验。
  - `operation_undo.py`：`_DELETE_RECORD` 加 `"create_checkup_report"`；删除时 `record_ids = data.get("record_ids") or [data["record_id"]]` 逐条删（问题先删、报告后删；RecordNotFound 视为已撤销）。
  - `create_checkup_report.ts`：`approval: always()`，inputSchema 用 zod 对应上面的字段（`date: z.iso.date()`、`metrics` 为键枚举 `weight_kg|systolic|diastolic|fasting_glucose|hemoglobin|fetal_heart_rate|fundal_height_cm` 的 record、`attachmentIds` 驼峰转下划线照 `create_record.ts`），execute 带 `approved: true`。
  - 指令：读到产检报告图片时，用 `create_checkup_report` 而不是 `create_record`；看不清的不填不猜；`flag` 只按单子上的箭头/标记或参考范围；异常项写成「想问医生的问题」（≤5）不写结论；工具确认后告诉用户可以在资料库看到。
- [ ] **Step 3**：API 全量、`make contracts`、Agent 测试（approval 断言加入 runtime-gate 或现有 approval 测试）。提交 `feat(agent): AIM 识别产检报告后一次建好报告与想问医生，可整批撤销`。

---

### Task 4: web 报告预览卡

**Files:**
- Create: `apps/agent-web/src/tools/CreateCheckupReport.tsx`
- Modify: `apps/agent-web/src/tools/index.tsx`（注册）
- Test: `apps/agent-web/src/tools/checkupReport.test.ts`（纯函数：指标显示名与单位、异常排序）

**Interfaces:**
- Consumes：工具参数（见 Task 3）；结果 `data.record_id`。
- Produces：卡片显示「将记下 / 已记下」+ 日期与医院、指标表（显示名：体重 kg、收缩压/舒张压 mmHg、空腹血糖 mmol/L、血红蛋白 g/L、胎心 次/分、宫高 cm）、其他化验项（flag 非空的排前并标色，箭头 ↑/↓/!）、将同时创建的问题列表、提示「看不清的项目没有填，请核对后确认」、`ApprovalSlot`、`ToolStatusLine`、`OpenNative kind="record" id={data.record_id}`。

- [ ] 纯函数 `metricRows(metrics)`、`sortedOtherItems(items)` 写在 `checkupReport.ts` 并测试；组件照 `CreateKnowledge.tsx` 结构。
- [ ] `npm test` + `npm run build`；提交 `feat(web): 产检报告预览卡`。

---

### Task 5: iOS 模型、撤销解析与上传

**Files:**
- Modify: `apps/ios/AimApp/Features/Records/RecordModels.swift`（`CheckupRecordData` 四段文字改可选、`otherItems`；`QuestionRecordData.reportID`）
- Modify: `apps/ios/AimApp/Features/Library/MetricTrend.swift`（`CheckupMetrics` 加 `fetalHeartRate`、`fundalHeightCm`）
- Modify: `apps/ios/AimApp/Generated/OpenAPI/Models.swift`（DTO 编解码；checkup 不再要求四段文字）
- Modify: `apps/ios/AimApp/Features/Agent/AgentStore.swift`（撤销结果解析改宽松，支持 `record_ids` / `tasks[]`）
- Modify: `apps/ios/AimApp/Clients/BusinessAPIClient/BusinessRepository.swift`（`uploadAttachment(jpeg: Data) async throws -> UUID`；创建/更新记录可带 `attachmentIDs`）
- Test: `Tests/CheckupMetricsRoundTripTests.swift`、`Tests/AgentStoreTests.swift`（撤销解析）、`Tests/BusinessRepositoryTests.swift`（上传请求形状，若有 URLProtocol 桩则复用）

**Interfaces:**
- Produces：`CheckupRecordData(hospital: String?, examItems: String?, result: String?, doctorAdvice: String?, metrics: CheckupMetrics, otherItems: [CheckupOtherItem])`；`CheckupOtherItem { name, value, unit?, reference?, flag: CheckupFlag? }`；`CheckupFlag: high/low/abnormal`；`QuestionRecordData.reportID: UUID?`；`AgentUndoTarget` 支持多个记录 `records([UUID])`；`repository.uploadAttachment`。

- [ ] 测试先行：DTO 解码只有 metrics 的 checkup 不再是 `.unknown`；other_items 往返；`reportID` 往返；撤销解析：`{"tasks":[{"task_id":…}], "failed":[]}` 得到多个任务目标、`{"record_ids":[…]}` 得到多个记录目标、旧 `{"record_id":…}` 仍可用、`attachment_count` 为整数不再导致解析失败。
- [ ] 所有使用 `CheckupRecordData` 四段文字的地方改为可选显示（编译器指出的位置逐一处理；空值不显示该行）。
- [ ] 上传：`POST /api/v1/pregnancies/{id}/attachments`，`Content-Type: image/jpeg`，body 原始字节；客户端压缩到 ≤2 MB（长边 ≤2048、质量逐步降低）。
- [ ] 单元测试全过；提交 `feat(ios): 报告模型、撤销整批解析与图片上传`。

---

### Task 6: iOS 报告表单、报告详情与本周关注

**Files:**
- Modify: `apps/ios/AimApp/Features/Records/RecordComposerView.swift`、`apps/ios/AimApp/Features/Library/CheckupMetricInput.swift`（全部 7 项指标、其他化验项行、照片 ≤4、四段文字可选）
- Create: `apps/ios/AimApp/Features/Records/CheckupReportView.swift`（报告详情；登记 pbxproj，照 `Features/Records` 下现有文件四处登记，编号取当前最大 +1）
- Modify: `apps/ios/AimApp/Features/Library/LibraryCategoryDetail.swift:205-217`（历次记录行可点进报告详情）、`RecordDetailView.swift`（checkup 类型改为展示 `CheckupReportView` 内容或跳转）、编辑权限 `canEdit`（family 可见 → 任何成员；private → 作者）
- Modify: `apps/ios/AimApp/Features/Library/LibraryFocus.swift`（新规则）
- Test: `Tests/LibraryFocusTests.swift`、`Tests/CheckupReportTests.swift`（对比上次的纯函数）、UI 用例一条

**Interfaces:**
- Produces：`CheckupComparison.make(current: CheckupRecordData, previous: CheckupRecordData?) -> [MetricDelta]`（`MetricDelta { kind, value, delta: Double?, unit }`）；本周关注规则 `abnormalReport`。

- [ ] 测试先行：对比函数（有上次/无上次/某指标上次缺失）；本周关注：30 天内最新报告 2 项 flag、无对应问题 →「最近报告有 2 项异常，记得问医生」；已有 `report_id` 对应且覆盖全部异常项的问题 → 不提示；31 天前 → 不提示；血压规则仍优先。
- [ ] 报告详情：日期、医院、照片缩略图（复用 `AttachmentThumbnail`/`AttachmentViewer`）、指标与上次对比（「↑ 0.8 kg」）、其他化验项（异常标色排前）、结果与医嘱；操作：编辑、问 AIM（上下文带小写记录编号与异常项）、「把异常项加入想问医生」（每项一条 question，`report_id` 指回，已存在的不重复加）、删除（二次确认）。
- [ ] 表单：指标 7 项（体重、收缩压、舒张压、空腹血糖、血红蛋白、胎心、宫高）带范围校验；其他化验项可增删行（名称、数值、单位、参考范围、异常选择）；照片选择 ≤4（PhotosPicker），保存时先上传再建记录；四段文字可选；编辑模式回填全部字段。
- [ ] UI 用例：新建一条带胎心 145 与一项「尿蛋白 + 异常」的产检记录 → 资料库产检列表点进报告详情 → 看到「尿蛋白」与「异常」标记 → 点「把异常项加入想问医生」→ 想问医生页出现该问题。
- [ ] 单元测试、该 UI 用例、`testEncyclopediaTopicEntryAndAskAIM` 回归通过；提交 `feat(ios): 产检报告表单与详情、异常项加入想问医生、本周关注提示报告异常`。

---

### Task 7: 端到端核对

- [ ] 重建 api、eve；`npm run build --prefix apps/agent-web`。
- [ ] 临时 XCUITest：注册 → 首页「拍报告」不便在模拟器选图时，改为在 AIM 输入框用文字描述「我今天产检：胎心 145，尿蛋白 +，血红蛋白 105 偏低，帮我记一下」→ 断言出现预览卡（含「胎心」「尿蛋白」）→ 点确认 → 资料库产检列表出现该报告并能进详情。跑完删除，不提交。
- [ ] 记录结果；无代码提交。
