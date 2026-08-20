# 完成待办时提示补记录 设计规格

## 1. 目标

任务完成时，除了灰色删除线记入时间线，用户往往还需要把完成时的结果单独记下来——最典型的是产检类待办，完成后应该记一下去了哪家医院、查了什么、结果如何。当前 iOS 客户端完成任务和创建记录是两条互不相关的路径，用户需要自己想起来再手动开记录表单。

本次范围是给「完成任务」这个动作加一个轻量的记录入口，不改变记录本身的领域模型，也不引入新的后端字段。

## 2. 已确认的产品决策

- 所有任务完成后都触发提示，不区分任务类型；类型只影响预填内容，不影响是否提示。
- 提示是轻量、非阻塞的：完成后原地出现一个可忽略的入口，不強制用户处理，不打断后续操作。
- 完成任务的两个入口——任务详情页的「标记完成」按钮、时间线上的左滑完成——都触发同样的提示。
- 点击提示进入记录表单时，按任务标题做关键词匹配预填记录类型（产检 vs 随手记）和标题/检查项文字；用户仍可在表单里改类型和内容。

## 3. 方案选择

复用已有的 `AimToast` 组件（[AimToast.swift](apps/ios/AimApp/Core/DesignSystem/Components/AimToast.swift)），把 Agent 撤销提示用的「文案 + 一个操作按钮 + 自动消失」结构原样搬过来，操作按钮从「撤销」换成「记一下」。

放弃常驻横幅方案：需要额外持久化"哪些任务还有未处理的记录提示"，且和当前完成即走的轻量交互模式不一致，复杂度不成比例。

放弃交给 Agent 判断方案：任务规定所有完成都要提示，如果每次都发起一次 Agent 会话判断要不要提示，等于每完成一件小事都打一次模型调用，延迟和失败面都不必要地变大，也偏离本次重设计反复强调的克制原则。

## 4. 类型推断

新增 `apps/ios/AimApp/Features/Records/TaskRecordSuggestion.swift`，纯函数，不依赖任何 View 或 Store：

```swift
enum TaskRecordSuggestion {
    static func recordType(forTaskTitle title: String) -> RecordType
}
```

关键词命中产检类词汇（产检、检查、复诊、B超、彩超、超声、抽血、验血、糖耐、唐筛、NT、四维、OGTT、建档、胎心监护、胎监、尿检、血压）之一时返回 `.checkup`，否则返回 `.note`。

这是启发式判断，允许猜错——新建记录时类型本来就可以在表单里改，猜错的代价只是多点一次，不影响正确性。

## 5. `AimToast` 复用与接口调整

`AimToastMessage` 已有 `text`、`undoTitle`、`undo` 三个字段，完成任务时直接换文案复用：

```swift
AimToastMessage(text: "已完成「\(task.title)」", undoTitle: "记一下") {
    recordPromptTask = task
}
```

`AimToast.swift` 内部目前把 `.accessibilityIdentifier("agent-undo-toast")` 写死在组件里。现在同一个组件要服务两种场景（Agent 撤销、完成待办提示记录），标识符需要参数化：

- `AimToastMessage` 增加 `accessibilityIdentifier: String = "aim-toast"` 字段。
- `AgentSheet`/`AgentStore` 相关调用点显式传 `"agent-undo-toast"`，保持既有标识符不变。
- 完成任务的调用点传 `"complete-task-record-prompt"`。
- `AimToastModifier` 内的 `.accessibilityIdentifier("agent-undo-toast")` 改为读取 `message.accessibilityIdentifier`。

## 6. 记录表单预填

`RecordComposerView.init` 增加两个可选参数，只在新建记录（`record == nil`）时生效，编辑已有记录时完全不受影响：

```swift
init(
    store: RecordStore,
    record: RecordItem? = nil,
    suggestedType: RecordType? = nil,
    suggestedText: String? = nil,
    onSaved: @escaping () -> Void
)
```

- `_type` 的初始值改为 `source?.type ?? suggestedType`。
- `_title`（`note` 类型用）初始值改为 `source?.title ?? (suggestedType == .note ? suggestedText ?? "" : "")`。
- `_examItems`（`checkup` 类型用）初始值改为 `source?.examItems ?? (suggestedType == .checkup ? suggestedText ?? "" : "")`。

`suggestedText` 统一传任务标题——不论落在 `note.title` 还是 `checkup.examItems`，语义都是"这条记录是关于什么"，用同一段文字预填是自然的。

现有调用点（`TimelineView` 的「新增记录」按钮、`RecordDetailView` 的编辑入口）不传这两个新参数，保持原有行为不变。

## 7. 接入完成入口

### 7.1 store 层：完成方法必须报告成功与否

`TimelineStore.complete(_ task:)` 当前签名是 `func complete(_ task: TaskItem) async`，失败时只写 `errorMessage`，调用方无法区分成功/失败。改为：

```swift
@discardableResult
func complete(_ task: TaskItem) async -> Bool
```

成功返回 `true` 且照常 `await load()`；失败写 `errorMessage` 并返回 `false`。只有返回 `true` 时才弹记录提示，避免"任务其实没完成，却提示要不要记一笔"的错乱。

`TaskDetailStore.complete()` 已经返回 `Bool`（[TaskDetailStore.swift:17](apps/ios/AimApp/Features/TaskDetail/TaskDetailStore.swift:17)），不需要改动，直接用它的返回值判断是否弹提示。

### 7.2 `TimelineView`

滑动完成的按钮动作里，`store.complete(task)` 返回 `true` 时设置 toast：

```swift
Button {
    Task {
        if await store.complete(task) {
            completedTaskID = task.id
            toast = AimToastMessage(
                text: "已完成「\(task.title)」",
                undoTitle: "记一下",
                accessibilityIdentifier: "complete-task-record-prompt"
            ) {
                recordPromptTask = task
            }
        }
    }
}
```

新增 `@State private var recordPromptTask: TaskItem?`，配合一个 `.sheet(item:)`：

```swift
.sheet(item: $recordPromptTask) { task in
    RecordComposerView(
        store: recordStore,
        suggestedType: TaskRecordSuggestion.recordType(forTaskTitle: task.title),
        suggestedText: task.title
    ) {
        recordPromptTask = nil
        Task { await store.load() }
    }
}
```

`recordStore` 是 `TimelineView` 已有的属性，直接复用，不需要新建。

### 7.3 `TaskDetailView`

「标记完成」按钮成功后弹同样的 toast。`TaskDetailView` 目前没有 `RecordStore`，需要新建一个并接上现有 repository：

```swift
@State private var recordStore = RecordStore()
```

在 `.task` 或 `init` 阶段设置 `recordStore.repository = store.repository`（`store` 是已有的 `TaskDetailStore`）。「标记完成」按钮的动作和 sheet 呈现与 7.2 对称。

## 8. 不做的事

- 不做"用户可以关闭这个提示功能"的开关——如果后续证明所有任务都提示确实太吵，那是需要新决策的产品问题，不在本次范围内预先加开关。
- 不持久化"哪条任务还欠一条记录"——提示消失后就消失，不留痕迹、不追踪、不提醒第二次。
- 不改变 `RecordItem`/`RecordDraft` 领域模型，不涉及后端。

## 9. 测试

- `TaskRecordSuggestionTests`：产检关键词命中用例（如「预约下周的系统超声检查」→ `.checkup`）、不命中用例（如「晚饭后散步 20 分钟」→ `.note`）、空标题边界情况。
- `RecordComposerView` 预填行为：`suggestedType`/`suggestedText` 只在 `record == nil` 时生效；传入已有 `record` 时预填参数被忽略，编辑行为不变。
- UI 测试：在时间线上左滑完成一个任务 → toast 出现且文案含任务标题 → 点击「记一下」→ 记录表单弹出且类型/文字已按预期预填。

## 10. 验收标准

1. 完成任意任务（详情页按钮或时间线滑动）后出现「记一下」提示，5 秒后自动消失，不点击也不影响后续操作。
2. 点击「记一下」打开的记录表单类型和文字已按任务标题预填，且仍可修改。
3. 任务完成失败（网络错误等）不触发提示。
4. 编辑已有记录的入口不受此改动影响。
