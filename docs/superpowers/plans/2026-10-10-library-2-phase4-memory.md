# 资料库 2.0 第 4 期：AIM 记得的事 实施计划

> **For agentic workers:** 使用 executing-plans 技能按任务实施并记录验证结果。

**Goal:** 用户和 AIM 能保存稳定事实，用户能查看、编辑、删除和控制可见性，后续对话读取当前有效记忆。

**当前结果（2026-10-10）：** 已完成，见 `../reports/2026-10-10-library-2-phase4-validation.md`。

**Architecture:** 复用 records 与既有授权、工具幂等和撤销机制。记忆属于当前孕期的家庭档案；所有读取都以当前账号、家庭、孕期过滤。50 条上限按整个家庭计算，包含私有记忆；创建时锁家庭行，避免并发突破上限。无需新增表或迁移。

**Tech Stack:** FastAPI / SQLAlchemy / pytest、Eve 动态指令与工具、React / vitest、SwiftUI / XCTest。

依据：`../specs/2026-10-09-library-2-design.md` §5.3、§6.4、§7.4。

## 实施决定

- `structured_data = {kind, text}`，kind 六类，text 去两侧空白后 1–80 字，禁止其他字段；标题由 text 前 40 字生成。新增、编辑统一校验。
- 当前孕期的记忆不自动继承到其他孕期，避免把上一孕期的用药等过时事实直接注入。家人可编辑家庭记忆；只有作者可改变可见性，私有记忆只有作者能访问。
- `remember` 直接执行可撤销；`forget_memory` 必须审批，且只能删除 memory 类型，不能变成通用删除记录入口。
- 本机 Eve 0.67.2 的 session.started 指令会与 turn.started 指令同时保留。为避免编辑、删除或改为私有之后仍注入旧快照，记忆在 **turn.started** 重新读取（包含会话第一轮），只写入当轮指令，不建立长期会话快照。读取失败返回 null，不阻断对话；动态上下文必须经过已验证的 session auth。
- 注入带来源成员与当前对话账号，未说明主体的个人事实只用于来源成员。注入内容以 JSON 数据表示，明确它是用户事实而非执行指令；不从记忆改变授权或工具边界。无记忆返回 null；稳定事实只在用户表达后保存，禁止记推测、瞬时状态及用户要求不记的内容。

## Task 1：后端记录与容量

**Files:** records/domain/record.py、application/commands/create_record.py 与 update_record.py、application/ports.py、adapters/outbound/persistence/repositories.py。

- [x] 先加领域测试：六类合法；未知类别、空白、81 字、额外键拒绝。
- [x] 在 RecordType 增加 memory；创建与编辑规范化 text、自动生成 title。
- [x] 仓储增加 `reserve_memory_slot(family_id)`：锁 FamilyModel 行，再数该家庭有效 memory；达到 50 抛出「记忆已满，请先整理」；所有创建入口复用。
- [x] 集成测试：新增、PATCH、删除后名额恢复；私有隔离；家人编辑与作者专属可见性；并发第 50 条。
- [x] `make -C services/api test` 通过后提交。

## Task 2：内部工具

**Files:** agent_access/adapters/inbound/http/router.py 与 operation_undo.py。

- [x] `POST /list-memories` 复用 list_records 可见性查询，仅返回当前孕期 memory。
- [x] `POST /remember` 用 create_record 创建家庭可见记忆，加入 DIRECT_EXECUTION_TOOLS，返回 record_id、kind、text、title。
- [x] `POST /forget-memory` 请求 id、approved；先鉴权、读可见记录并验证类型，再删除。未批准返回 approval_required；其他类型及跨家庭访问不允许。
- [x] remember 加入新建记录撤销组，遗忘不支持撤销且在文案中说明。
- [x] 测试审批、幂等、撤销和私有/跨家庭隔离；`make contracts` 后提交。

## Task 3：AIM 工具、动态记忆与网页卡片

**Files:** services/agent/agent/tools/remember.ts、forget_memory.ts、instructions/memory.ts、instructions.md、lib/business-api/client.ts；apps/agent-web/src/tools/Memory.tsx、labels.ts、turnWrites.ts。

- [x] 创建 remember / forget_memory（always approval）工具，list_records 类型增加 memory；编译清单只增加预期工具。
- [x] 动态指令通过 session auth 调只读 list-memories；限定超时，失败仅记非敏感日志，返回 null；测试空、有效、失败和作用域 headers。
- [x] 网页展示已记住的具体内容、撤销、原生查看；遗忘卡展示待确认/已遗忘/失败等真实状态。
- [x] 注册写入刷新与工具中文名；保留既有工具审批边界。
- [x] Agent 测试、lint、build 和网页测试/build 通过后提交。

## Task 4：iOS 记忆管理

**Files:** RecordModels.swift、Generated/OpenAPI/Models.swift、RecordsView.swift、RecordDetailView.swift、LibraryCatalog.swift、LibraryCategoryDetail.swift、Features/Library/MemoryView.swift 与工程登记。

- [x] Codable 接通 memory 类型与六类；未知类别安全显示且不能被错误保存。
- [x] 资料库新增「AIM 记得的事」卡，按类别分组；说明、新增、编辑、删除确认、作者可见性开关、问 AIM。
- [x] 统一表单选类型与一句话；1–80 字校验，错误保留草稿。AIM 卡片查看落到原生记忆详情。
- [x] AgentUndoTarget 识别 remember，刷新沿用 record 事件。
- [x] XCTest 验证 DTO 往返、权限、长度；UI 完成新增→编辑→私有→删除，再回归报告流程。通过后提交。

## Task 5：真实模型验收与合并

- [x] 只重建本地 api、eve，网页构建；确认真实模型启用。
- [x] 对 AIM 说一条稳定偏好，验证记忆卡与资料库保存；新对话在不重复该偏好的情况下读到它。
- [x] 手动编辑后，新对话读取新值；删除后 list-memories 不返回，后续上下文不注入；遗忘工具确实先显示确认。
- [x] 私有记忆的隔离由 API 两账号测试覆盖，不将真实模型对话当授权证据。
- [x] `make verify`、iOS 单元/UI、截图检查；更新路线图与验收记录，合并本地 development。
