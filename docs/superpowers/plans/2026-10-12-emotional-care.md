# 情绪关照 Implementation Plan

> **For agentic workers:** 使用 executing-plans 顺序实施。本次用户已授权持续实现与验证，不另建对话、不调用子代理。

**Goal:** 每日心情与 EPDS 自评可在原生 App 使用、私密保存、按确定规则评分，并始终能进入求助。

**Architecture:** records 领域负责校验和派生分数；单一 JSON 资源保存题目与计分表并打入 bundle；原生独立 store 处理表单与历史，首页及记录详情复用支持卡。提醒纯函数预留真实分娩日期，产后功能实施时接入。

**Tech Stack:** FastAPI/SQLAlchemy、SwiftUI/Observation、XCTest/XCUITest、Eve/TypeScript。

## Task 1：来源、领域与权限

**Files:** 新建 `content/mental-health/epds-zh-Hans.json`、`services/api/src/aim_api/contexts/records/domain/mental_health.py`、`services/api/tests/domain/records/test_mental_health.py`；修改同级 `record.py`、`application/commands/update_record.py` 与 `composition/family/activity.py`。

- 先写原始选项评分与风险优先、非法输入、伪造分数覆盖测试。
- 计分：`sum(index if question in {1,2,4} else 3-index for each answer)`；第十项独立优先。
- records 增加两种类型与校验；分享情绪记录仍作者-only 修改删除。补 HTTP 私有读取/共享只读集成测试。
- API 合同重新生成；保留原 records 表，不新增迁移。

## Task 2：原生模型与表单

**Files:** 新建 `apps/ios/AimApp/Features/EmotionalCare/EmotionalCareModels.swift`、`EmotionalCareStore.swift`、`EmotionalCareView.swift`、`EmotionalSupportCard.swift`；修改 `Features/Records/RecordModels.swift`、`RecordsView.swift`、`RecordDetailView.swift`、`RecordComposerView.swift`、`Generated/OpenAPI/Models.swift` 与 `AimApp.xcodeproj/project.pbxproj`。

- 加载并验证 bundle 的十题、四选项与分值；来源和版权常驻。
- 今日心情按本人和北京时间匹配；保存默认私密。表单失败保留草稿。
- EPDS 全答才能保存；第十题选择非零分立即展示支持卡。用服务端结果重新确认分数。
- 新类型用专用编辑/详情，不落入通用未知类型或让一条记录解码失败影响整页。
- 针对 scorer、节点判断、私有默认、保存失败、作用域切换写模型/store 测试。

## Task 3：首页、AIM 与验收

**Files:** 修改 `Features/Home/HomeDashboardView.swift`、`services/agent/agent/tools/list_records.ts`、`services/agent/agent/instructions.md`、`services/agent/tests/instructions.test.ts`、`apps/ios/AimApp/UITests/CoreJourneyUITests.swift`。

- 首页可到心情页；妈妈可做 EPDS，家人看到适用范围说明与自己的心情入口。
- AIM 可按权限读用户情绪记录，但不代填、算诊断或创建量表。只使用确定的已有结果，当前诉求优先于历史记录。
- UI 验收默认私密心情保存、未完成量表的即时求助卡、完成并保存后历史可见。
- `make verify`、iOS 单元测试与必要 UI 旅程通过后，更新路线图与验收报告、提交并合并本地 development。

## Task 4：产后节点交接

- 产后第 14/42 天的纯函数和测试在本项完成；第 9 项真实分娩日期接入后验证实际首页与自评记录节点。
- 没接入前明确报告范围，不把未启用的产后提示报成已实测。
