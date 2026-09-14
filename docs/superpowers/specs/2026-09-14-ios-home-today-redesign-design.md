# iOS 首页改为「今天」总控、时间线降为次级页 设计规格

## 1. 背景与目标

2026-08-18 的重设计把「今天 / 计划 / 记录」合并为一条以孕周为刻度的连续时间线，并让它直接充当首页。上线一个月后暴露出三个问题：

1. **每次进入都要滚到底部才能看到今天。** 时间线只在首次出现时用 `ScrollViewProxy.scrollTo` 跳一次「今天」，目标是 Section 头；`List` 懒加载，行尚未排版时这一跳静默失败。早期过去内容少、今天本来在首屏，问题被掩盖；随着已完成任务和记录累积，今天被推到底部。「回到今天」按钮同样失效：它靠今天分组头的 `PreferenceKey` 位置判断，而 `List` 会卸载滚出屏幕的行，偏好值回落到默认 0，按钮反而不出现。
2. **没有手动新建待办的入口。** 头部 `+` 只打开记录表单。后端 `POST /pregnancies/{id}/tasks` 已存在，客户端只在「从记录创建任务」时调用。
3. **首页作为一条列表显得简陋。** 首页的主语应当是「今天要做什么」，而不是一条两头无限增长的时间轴。

根因是同一个：把「今天」放在一条向两头增长的列表中间，首页永远需要先找到今天。本规格把首页改为以今天为顶的总控页，时间线降为从首页进入的次级页。这与产品方案 §9.1「今天：总控首页」和「首页以家庭状态和下一步行动为中心」一致，也是原型最初的今天页方向。

范围只覆盖 iOS 客户端。服务端契约、Eve Runtime 不改。

## 2. 已确认的决策

- 采用方案 B：首页 = 今天总控，时间线 = 次级页。方案 A（仅折叠过去周、修 bug）被否决。
- 新建待办同时提供两种入口：今天列表底部的行内快速添加，以及 `+` 菜单里的完整表单。
- 底部 Tab 仍为四个：`孕期`、`资料库`、`AIM`、`家庭`。Tab 名保持「孕期」，因为它同时承载今天页与时间线页。
- 设计 token、字阶、几何沿用 2026-08-18 规格 §5，不新增颜色。

## 3. 信息架构

```
Tab 孕期
└── 今天（首页，NavigationStack 根）
    ├── 头部：日期 · 阶段 / 孕 N 周 + d 天（可点，进时间线）/ + 菜单 / Agent
    ├── 焦点卡「现在最重要」
    ├── 今天 · N 项（含逾期，行内勾选，底部「添加待办」）
    ├── 接下来 7 天
    ├── 最近记录
    ├── 「查看完整时间线 →」
    └── push → 孕期时间线（次级页）
          ├── 顶部一行「之前 · 孕 a–b 周 · N 项」默认折叠
          ├── 本周（今天所在）
          ├── 未来 4 周展开，更远折叠（沿用现有规则）
          └── 工具栏：筛选
```

## 4. 首页「今天」

### 4.1 头部

沿用 `TimelineHeader` 的布局，做三处改动：

- 小字行改为「9月14日 周一 · 孕中期」。阶段按孕周三分：≤13 周孕早期、14–27 周孕中期、≥28 周孕晚期，客户端本地计算。
- 大标题「孕 22 周 + 6 天」后加一个 `chevron.right` 小图标，整块是进入时间线的 `NavigationLink`。这是时间线的主入口。
- 右侧按钮从三个减为两个：`+` 和 Agent。筛选按钮移到时间线页。`+` 改为 `Menu`，两项：「新建待办」「新增记录」。

### 4.2 焦点卡

沿用 `AimFocusCard`，改焦点任务的选取规则：

1. 截止时间 ≤ 今天 23:59 的未完成任务里，取截止最早的一条（逾期优先于今天）；
2. 没有则取所有未完成任务里截止最早的一条；
3. 没有未完成任务则不显示焦点卡。

焦点任务从下面的「今天」「接下来」列表中排除，卡片是它唯一入口。副标题行显示「负责人 · 相对日期」，主按钮「开始处理」进任务详情，与现状一致。

### 4.3 今天 · N 项

分组头「今天 · N 项」，N 为本组行数；若有逾期，头部右侧显示陶土色「逾期 M」，仅此一处用 `aimDanger`。

入组规则：未完成、且（截止时间 ≤ 今天 23:59 或没有截止时间）的任务，排除焦点任务。排序：逾期在前，按截止时间升序，无截止时间的排最后。

行：沿用 `AimTaskRow`，但 checkbox 变为可点：

- 点击 → 调 `complete`，触觉 `.success`，弹出现有「已完成 … / 记一下」toast。请求中该行 checkbox 显示 `ProgressView`，失败则 toast 报错，行保持原状。
- 行本身仍是 `NavigationLink` 进详情。
- 右滑完成（保留，与 checkbox 等价）、左滑延期，沿用现有 `swipeActions`。
- 元信息行的日期改为相对格式，见 §7。逾期任务日期前缀「逾期 · 」，用 `aimDanger`。

空态：没有今天任务时显示一行灰字「今天没有安排」，「添加待办」行仍然在。

**添加待办行**（本组最后一行）：`plus` 图标 + 「添加待办」灰字。点击后该行变为 `TextField`，自动聚焦，提示文字「要做什么」。回车提交，失焦或提交空文本则恢复原状。提交时该行显示 `ProgressView`；成功后 reload，输入框清空并保持聚焦，方便连续录入；失败在该行下方显示错误一行，输入内容保留。快速添加的截止时间固定为今天 23:59，负责人为空。

### 4.4 接下来 7 天

分组头「接下来 7 天」。入组：未完成、截止时间在明天 00:00 到第 7 天 23:59 之间的任务，排除焦点任务，按截止升序，最多 5 行。超过 5 行时末尾一行「还有 N 项 · 查看时间线」进时间线。本组为空时整组隐藏。行样式与今天组一致，checkbox 用虚线圆表示「还没到」，但同样可点完成。

### 4.5 最近记录

分组头「最近记录」，右侧「全部」文字按钮进时间线。列出按 `occurredAt` 倒序的前 3 条记录，沿用 `AimRecordRow`，点击进 `RecordDetailView`。没有记录时显示一行灰字「还没有记录」。

### 4.6 底部

最后一行「查看完整时间线」陶土色文字 + 箭头，进时间线。为它下方留 `safeAreaPadding`，不被 Tab 栏遮挡。

### 4.7 容器

首页主体继续使用 `List(.plain)` + `.scrollContentBackground(.hidden)`，理由与 2026-08-18 规格 §3.2 相同：`swipeActions`、`refreshable`、键盘规避（快速添加的输入框需要）都由系统负责。不再绘制时间轴导轨；`listRowBackground` 用 `aimCanvas`。三个分组头（今天、接下来 7 天、最近记录）不吸顶：plain 样式的 `Section` header 会吸顶，所以分组头作为普通行放在各组第一行，用 `aimLabelStyle`，`accessibilityAddTraits(.isHeader)`。

### 4.8 状态优先级

沿用 2026-08-18 规格 §7.1。首页判定顺序：未配置孕期 → 引导态；加载中且无数据 → `ProgressView("正在整理今天")`；失败且无数据 → `AimErrorState` 含重试；失败但有数据 → 展示数据 + 顶部错误条；成功 → 内容。首页永远显示头部与「添加待办」行，「成功且无数据」不再是空态。

## 5. 时间线（次级页）

从首页 push 进入，`navigationTitle("孕期时间线")`、`.inline`，返回键回到今天。主体复用现有 `TimelineView` 的 List 与导轨，做以下改动：

- **过去周折叠成一行。** 所有 `position == .past` 的周默认折叠为列表第一行「之前 · 孕 a–b 周 · N 项」（`a`、`b` 为最早与最晚过去周，N 为条目总数）。点击展开全部过去周，再点收起。展开状态只在本次进入时间线期间保留。没有过去内容时不显示这一行。
- 因此**今天所在周默认就是第一个分组**，不再需要启动时 `scrollTo`。删除 `.task { proxy.scrollTo(...) }` 和 `TodayOffsetKey`。
- **「回到今天」按钮**改为：仅在过去周展开时显示；点击 = 收起过去周 + `scrollTo(todayAnchor, anchor: .top)`。收起后今天本来就在顶部，`scrollTo` 失败也无碍。
- 今天所在周的分组头仍是唯一陶土色，标题仍为「今天」。本周分组里不再放焦点卡（焦点卡只在首页），焦点任务作为普通行出现。
- 未来周规则不变：近 4 周展开，更远折叠为「孕 N 周 · M 项」行。
- 筛选 `Menu` 放在工具栏右侧，选项与现有 `TimelineFilter` 一致；选中非「全部」时图标变陶土色。
- 头部不再重复「孕 N 周 + d 天」大标题，那是首页的事。
- 下拉刷新、滑动完成 / 延期、行点击进详情，全部沿用。

## 6. 新建待办

### 6.1 数据层

`BusinessRepositoryProtocol` 新增：

```swift
func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem
```

实现 `POST /api/v1/pregnancies/{pregnancy_id}/tasks`，body 字段 `title`、`description`、`due_at`、`assigned_member_id`，`source_type` 用服务端默认 `user`。现有 `CreateTaskFromRecordBody` 改为通用的 `CreateTaskBody`（多两个可选字段），`createTaskFromRecord` 改为调用同一个 body 类型。测试目录下所有 `BusinessRepositoryProtocol` 的假实现（`FakeLibraryRepository`、`CountingRepository`、`DeletingRepository`、`SpyRepository` 等）补齐该方法。

`TimelineStore` 新增：

```swift
@discardableResult
func createTask(title: String, description: String? = nil, dueAt: Date?, assignedMemberID: UUID? = nil) async -> Bool
```

成功后调 `load()` 并返回 true；失败写 `errorMessage` 返回 false，与 `complete(_:)` 一致。

### 6.2 快速添加

见 §4.3。标题去首尾空白后为空则不提交。

### 6.3 完整表单 `TaskComposerView`

`+` 菜单「新建待办」弹出 sheet，`.presentationDetents([.medium, .large])`：

| 字段 | 控件 | 默认 |
| --- | --- | --- |
| 标题 | `TextField`，必填 | 空 |
| 说明 | `TextField(axis: .vertical)` | 空 |
| 截止时间 | `Toggle("设置截止时间")` + `DatePicker`（日期 + 时间） | 开，今天 20:00；若已过 20:00 则明天 20:00 |
| 负责人 | `Picker`，选项「未指派」+ 家庭成员（`displayName`） | 未指派 |

导航栏「取消」「保存」。保存中按钮换 `ProgressView` 并禁用取消；失败在表单内显示 `aimDanger` 错误行，与 `TaskDelaySheet` 一致。成功后关闭并 reload。

## 7. 相对日期文案

新增纯函数 `TaskDateText.label(for date: Date, now: Date, calendar: Calendar) -> String`，首页与时间线的任务行元信息统一使用：

| 情况 | 文案 |
| --- | --- |
| 早于今天 | 「昨天」「3 天前」「9月2日」（超过 7 天） |
| 今天 | 「今天」 |
| 明天 | 「明天」 |
| 2–6 天内 | 「周三」 |
| 更远 | 「9月28日」 |

时间部分：若时刻不是 23:59（快速添加的哨兵值），在日期后追加「 19:30」。逾期由调用方加前缀，本函数不管。

## 8. 代码组织

| 改动 | 说明 |
| --- | --- |
| `Features/Timeline/TimelineStore.swift` | 保留为首页与时间线的共享数据源。新增派生属性 `focusTask`（新规则）、`overdueTasks`、`todayTasks`、`upcomingTasks`、`recentRecords`、`pastWeeks`、`stageName`，以及 `createTask`。`expandedFarWeeks` 保留，新增 `isPastExpanded` |
| `Features/Home/HomeView.swift`（新） | 首页。持有 sheet / toast / 快速添加状态 |
| `Features/Home/HomeHeader.swift`（由 `TimelineHeader` 改名并改造） | §4.1 |
| `Features/Home/TaskQuickAddRow.swift`（新） | §4.3 添加待办行 |
| `Features/Home/TaskComposerView.swift`（新） | §6.3 |
| `Features/Home/TaskDateText.swift`（新） | §7 |
| `Features/Timeline/TimelineView.swift` | 改为次级页，§5 |
| `Core/DesignSystem/Components/AimTimelineRows.swift` | `AimTaskRow` 增加 `isPending`（请求中）与虚线圆样式，日期改用 `TaskDateText` |
| `App/AimApp.swift` | Tab 根视图换成 `HomeView` |
| `Features/Today/TodayStore.swift`、`Tests/TodayStoreTests.swift` | 删除。这是合并三 Tab 时遗留的死代码，无调用点 |
| `Features/Today/TodayView.swift` | 文件里实际是 `PregnancySetupView`，移到 `Features/Onboarding/PregnancySetupView.swift`，`Features/Today/` 目录删除 |

## 9. 无障碍与标识符

- 快速添加输入框 `accessibilityLabel("添加待办")`，提交按钮语义由回车承担。
- checkbox 按钮 `accessibilityLabel` 为「标记完成」/「已完成」，行合并为单一元素，朗读顺序「状态 → 标题 → 负责人 → 日期 → 来源」。
- 标识符：`home-header-week`（进时间线）、`home-add-menu`、`home-focus-card`、`home-task-row`、`home-task-checkbox`、`home-quick-add`、`home-quick-add-field`、`home-open-timeline`、`task-composer-save`、`timeline-past-collapsed`、`timeline-back-to-today`、`timeline-filter`。现有 `timeline-week-header-{n}`、`timeline-task-row`、`record-row-{type}`、`complete-task-record-prompt`、`global-agent-button` 保留。
- Dynamic Type 与深色模式要求沿用 2026-08-18 规格 §9。

## 10. 测试

单元测试（XCTest，固定 `today` 与 `calendar`）：

- `TimelineStore`：焦点任务三条规则；今天组包含逾期与无截止任务、排除焦点任务、排序；接下来组只含明天到第 7 天；最近记录取前 3 条倒序；`pastWeeks` 范围与计数；`stageName` 三段边界（13/14、27/28 周）。
- `TaskDateText`：表格中每一行，含 23:59 哨兵不显示时间。
- `BusinessRepository.createTask`：请求路径、方法、body 字段名（`due_at`、`assigned_member_id`）与可选字段省略。
- `TimelineStore.createTask`：成功后触发 reload；失败返回 false 并写 `errorMessage`。

UI 测试（`CoreJourneyUITests`）：

- 现有「滑动完成 → 记一下」用例改为点 checkbox 完成。
- 新增：快速添加待办后该标题出现在今天组。
- 新增：点头部孕周进入时间线，`timeline-past-collapsed` 或 `timeline-week-header-{current}` 可见，返回回到首页。

## 11. 不在本次范围

- 「Aim 已处理事项」区块。`AgentStore.activityLog` 只在内存、启动即空，先不上首页。
- 时间线的向上分页加载。过去周折叠一行后，一次性展开的性能在孕期 40 周体量内可接受。
- 服务端 `/today` 的 `priority_task` 规则调整。客户端本地计算焦点任务，不依赖它。
- 记录照片、产后延展、多 Agent 可视化，同前一规格。

## 12. 验收标准

1. 冷启动与从其它 Tab 切回，首页首屏都能看到头部、焦点卡和今天组，无需滚动。
2. 过去有 30 周以上的已完成任务与记录时，进入时间线首屏第一行是「之前 · …」折叠行，第二个分组是「今天」。
3. 展开过去周并上滚后，「回到今天」出现；点击后过去周收起、今天在顶部。
4. 快速添加：输入标题回车，行内出现加载态，随后新任务出现在今天组，输入框保持聚焦。断网时错误显示在该行下方，输入不丢。
5. `+` 菜单「新建待办」表单可设截止时间与负责人，保存后出现在对应分组；失败在表单内可见。
6. 点 checkbox 完成任务：触觉反馈、toast 出现、任务离开今天组；时间线上该任务显示为已完成。
7. 逾期任务出现在今天组顶部，带「逾期 · 昨天」红色前缀，分组头显示「逾期 M」。
8. 深色模式与 `AX5` 字号下首页无截断、无白底白字。
9. 全部单元测试与 UI 测试通过。
