# 产后延续 Implementation Plan

> **For agentic workers:** 使用 executing-plans 在当前会话按任务顺序实施，用户已授权持续推进。

**Goal:** 真实分娩记录能把 Aim 切换为产后家庭照护，宝宝档案、日志、待办、情绪节点与提醒使用同一事实。

**Architecture:** pregnancy 增加生命周期字段，babies 为同孕期的家庭实体，三类照护日志复用 records；composition 事务统一阶段切换与任务衔接。确定性纯函数负责时间和日志统计，AIM 只操作授权事实。

**Tech Stack:** PostgreSQL/Alembic、FastAPI/SQLAlchemy、SwiftUI/Observation、Eve、pytest/XCTest/XCUITest。

**最终结果（2026-10-12）：** Task 1–5 的实现与开发验收完成，API 555、Agent 62、iOS 单元 538、网页 70 项通过；出生、照护编辑删除、日期修正、14/42 天自评、撤回恢复与核心回归通过。Release 发行导出通过。见 `../reports/2026-10-12-postpartum-validation.md`；生产部署仍遵守在用设备先升级的约束。

## Task 1：日期、生命周期与迁移

**Files:** `services/api/src/aim_api/platform/business_time.py`、`contexts/pregnancy/domain/pregnancy.py`、其 persistence models/repositories、`services/api/migrations/versions/0013_postpartum_babies.py`、相关日期/孕期单元测试。

- 先写北京时间跨日、出生日期、冻结出生孕周、撤回和日期修正测试。
- 加 `birth_date/birth_revision`、postpartum、BabyModel 与软归档；数据库迁移不改已有记录内容。
- 孕周与业务日期统一北京口径；未出生逻辑保持既有校验，产后校验预产期参考分娩日。

## Task 2：出生事务与计划

**Files:** 新建 `composition/postpartum/router.py`、`contexts/babies/` 与 `content/postpartum/`；修改 task 状态和取消/恢复操作、同步孕周的停止条件、bootstrap 路由、家庭动态与 pregnancy/today 输出。

- `POST birth` 行锁、幂等、可选档案、取消孕期待办、生成当前 revision 的产后安排、家庭事件，同一次 commit。
- 日期修正只更新系统默认且未完成安排；撤回仅在无后续事实时软归档与恢复，保留轨迹。
- 对照 2026 免疫程序写「核对安排」清单；日历月份来自真实生日。
- pytest 覆盖授权、重复、回滚、早期安排、用户改期保留与撤回边界。

## Task 3：照护日志与 AIM

**Files:** records domain/create/update/repository，`services/agent/agent/tools/list_babies.ts`、`record_baby_care.ts`、`list_records.ts`、instructions 与工具测试。

- baby_id 归属与事件时间验证放在写入边界；睡眠时长由服务端计算；权限遵守已有私密/家庭范围。
- AIM context 显示 postpartum 与宝宝事实；新工具只记用户明确提供的数据，不代切阶段。
- 重新生成契约，API 与 Agent 回归。

## Task 4：原生资料、阶段与表单

**Files:** 新建 `apps/ios/AimApp/Features/Postpartum/` 的 Models、Store、View 与 Forms；扩展 BusinessRepository、RecordModels/DTO/详情、HomeDashboard、LibraryCategoryDetail、LaborView、FamilyProfile、ReminderPlanner；登记项目与内容资源。

- 阶段与档案的接口 DTO 使用可选新字段，兼容旧后端读取。
- 首页根据状态显示；分娩确认、宝宝编辑、三类照护、可见统计、清单和日期修正/撤回。
- 统计睡眠按当天交集并合并重叠区间；未知奶量不编造为零或推荐值。
- 真实分娩日期传入情绪节点；产后胎动计划为零。相关确定性和 store 测试先于 UI 验收。

## Task 5：验收与交付

- 启动迁移后的本地栈，跑出生与日志 UI、产后节点、撤回恢复、既有情绪/分娩/提醒核心旅程。
- `make verify`、iOS 单元测试、迁移升级/幂等与 Release 发行导出。
- 更新第 8、9 项真实验收状态、报告和部署次序；合并本地 development。远端推送仍需用户明确授权；后端部署等待使用设备更新。
