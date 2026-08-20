# 完成待办时提示补记录 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成任意待办（任务详情页或时间线滑动）后，弹出一条可忽略的轻提示，点击「记一下」打开按任务标题预填类型和文字的记录表单。

**Architecture:** 新增一个纯函数做类型推断；复用已有的 `AimToast` 组件（把 Agent 撤销提示的文案换成「记一下」）；`RecordComposerView` 的初始化增加两个只在新建记录时生效的可选预填参数；两个完成入口（`TimelineView` 滑动完成、`TaskDetailView` 标记完成按钮）在完成成功后触发同一套 toast + sheet。

**Tech Stack:** SwiftUI（iOS 17+）、Observation、XCTest

## Global Constraints

- 部署目标 iOS 17.0，不使用 iOS 18+ API。
- **本工程的 `project.pbxproj` 使用显式文件引用，没有 `fileSystemSynchronizedGroups`。每新增一个 `.swift` 文件，必须手工添加三处条目**：`PBXFileReference`、`PBXBuildFile`、以及所属 `PBXGroup.children` 与对应 Sources 构建阶段的 `files` 列表。漏掉任何一处，文件不参与编译且不报错。
- 新 `PBXFileReference` ID 从 `A10000000000000000000058` 起递增；新 `PBXBuildFile` ID 从 `A20000000000000000000059` 起递增（已用最大值分别为 `...057` 与 `...058`，均已核实于当前文件）。
- 主 target 的 Sources 构建阶段是 `A30000000000000000000004`；测试 target `AimAppTests` 的是 `A30000000000000000000006`。
- 相关 PBXGroup：`Records` = `A40000000000000000000102`、`Tests` = `A40000000000000000000014`。
- 全部颜色必须来自 Assets colorset 引用（`Color.aim*`），不得出现 `Color(red:green:blue:)` 或系统 `.secondary`/`.red` 之外的裸色。
- 文案一律简体中文，句子不加感叹号，不使用「请」。
- 每个任务结束时提交，commit message 使用 `feat(ios):` / `fix(ios):` 前缀。
- 编译验证：`export DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer && make ios-build`（本机默认 Xcode 不在 `/Applications`，必须显式设置 `DEVELOPER_DIR`，不要用 `sudo xcode-select`）。
- 单元测试：同样设置 `DEVELOPER_DIR` 后，
  `xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppTests/<类名>`
- 若模拟器报 `Simulator device failed to launch ... Busy`，先 `xcrun simctl shutdown all` 再重试，这是模拟器残留状态导致的瞬时错误，不是代码问题。

---

### Task 1: 任务标题到记录类型的关键词推断

纯函数，不依赖任何 View 或 Store，TDD 实现。

**Files:**
- Create: `apps/ios/AimApp/Features/Records/TaskRecordSuggestion.swift`
- Create: `apps/ios/AimApp/Tests/TaskRecordSuggestionTests.swift`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `RecordType`（`Features/Records/RecordModels.swift` 中已有的 `symptom`/`checkup`/`note`/`unknown` 枚举）
- Produces: `enum TaskRecordSuggestion { static func recordType(forTaskTitle title: String) -> RecordType }`

- [ ] **Step 1: 写失败测试**

创建 `apps/ios/AimApp/Tests/TaskRecordSuggestionTests.swift`：

```swift
import XCTest
@testable import AimApp

final class TaskRecordSuggestionTests: XCTestCase {
    func testChecklistKeywordsMapToCheckup() {
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: "预约下周的系统超声检查"), .checkup)
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: "整理最近一次产检记录"), .checkup)
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: "去医院做糖耐测试"), .checkup)
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: "四维彩超预约"), .checkup)
    }

    func testUnrelatedTitlesMapToNote() {
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: "晚饭后散步 20 分钟"), .note)
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: "确认杭州生育待遇材料"), .note)
    }

    func testEmptyTitleFallsBackToNote() {
        XCTAssertEqual(TaskRecordSuggestion.recordType(forTaskTitle: ""), .note)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `export DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer && xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppTests/TaskRecordSuggestionTests`
Expected: 编译失败，`cannot find 'TaskRecordSuggestion' in scope`

- [ ] **Step 3: 实现**

创建 `apps/ios/AimApp/Features/Records/TaskRecordSuggestion.swift`：

```swift
import Foundation

enum TaskRecordSuggestion {
    private static let checkupKeywords = [
        "产检", "检查", "复诊", "B超", "彩超", "超声", "抽血", "验血",
        "糖耐", "唐筛", "NT", "四维", "OGTT", "建档", "胎心监护", "胎监", "尿检", "血压",
    ]

    static func recordType(forTaskTitle title: String) -> RecordType {
        checkupKeywords.contains { title.contains($0) } ? .checkup : .note
    }
}
```

- [ ] **Step 4: 注册到 pbxproj**

在 `apps/ios/AimApp.xcodeproj/project.pbxproj` 的 `Begin PBXFileReference section` 末尾（`/* End PBXFileReference section */` 之前）追加：

```
		A10000000000000000000058 /* TaskRecordSuggestion.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Features/Records/TaskRecordSuggestion.swift; sourceTree = "<group>"; };
		A10000000000000000000059 /* TaskRecordSuggestionTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/TaskRecordSuggestionTests.swift; sourceTree = "<group>"; };
```

在 `Begin PBXBuildFile section` 末尾（`/* End PBXBuildFile section */` 之前）追加：

```
		A20000000000000000000059 /* TaskRecordSuggestion.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10000000000000000000058 /* TaskRecordSuggestion.swift */; };
		A20000000000000000000060 /* TaskRecordSuggestionTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10000000000000000000059 /* TaskRecordSuggestionTests.swift */; };
```

把 `A10000000000000000000058` 加入 `Records` 组（`A40000000000000000000102`）的 `children`；把 `A10000000000000000000059` 加入 `Tests` 组（`A40000000000000000000014`）的 `children`。

把 `A20000000000000000000059` 加入主 target Sources 阶段（`A30000000000000000000004`）的 `files`；把 `A20000000000000000000060` 加入测试 target Sources 阶段（`A30000000000000000000006`）的 `files`。

- [ ] **Step 5: 运行测试确认通过**

Run: 同 Step 2 的命令
Expected: 3 个测试全部 PASS

- [ ] **Step 6: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): infer record type suggestion from task title"
```

---

### Task 2: Toast 标识符参数化 + 记录表单预填参数

两处独立但都很小的接口改动，合并为一个任务：一个是 `AimToastMessage` 的可访问性标识符从硬编码改为参数化，一个是 `RecordComposerView` 的初始化增加预填参数。两者都是本次功能的必要前置改动，且都没有可复用的单元测试基础设施（View 层改动在这个代码库里一贯靠编译验证 + 后续的端到端 UI 测试覆盖，没有 ViewInspector 之类的依赖）。

**Files:**
- Modify: `apps/ios/AimApp/Core/DesignSystem/Components/AimToast.swift`
- Modify: `apps/ios/AimApp/Features/Agent/AgentSheet.swift`（如果调用点需要显式传入标识符）
- Modify: `apps/ios/AimApp/Features/Records/RecordComposerView.swift`

**Interfaces:**
- Consumes: 无新依赖
- Produces:
  - `AimToastMessage(text:undoTitle:accessibilityIdentifier:undo:)`，新增 `accessibilityIdentifier: String = "aim-toast"` 字段
  - `RecordComposerView.init(store:record:suggestedType:suggestedText:onSaved:)`，新增两个可选参数

- [ ] **Step 1: 参数化 AimToastMessage 的标识符**

打开 `apps/ios/AimApp/Core/DesignSystem/Components/AimToast.swift`，把 `AimToastMessage` 改为：

```swift
struct AimToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    var undoTitle: String = "撤销"
    var accessibilityIdentifier: String = "aim-toast"
    var undo: (() -> Void)?

    static func == (lhs: AimToastMessage, rhs: AimToastMessage) -> Bool { lhs.id == rhs.id }
}
```

把 `AimToastModifier.toast(_:)` 方法末尾的 `.accessibilityIdentifier("agent-undo-toast")` 改为：

```swift
        .accessibilityIdentifier(message.accessibilityIdentifier)
```

- [ ] **Step 2: 确认现有 Agent 撤销调用点显式传入原标识符**

Run: `grep -rn "AimToastMessage(" apps/ios/AimApp --include="*.swift"`

若找到 Agent 侧构造 `AimToastMessage` 的调用点（撤销相关），在其构造参数中显式加上 `accessibilityIdentifier: "agent-undo-toast"`，保持既有标识符不变。若当前代码库里还没有任何调用点构造 `AimToastMessage`（`toast` 状态目前未被触发，属于 Task 7 遗留的死接线），跳过这一步，不需要新造一个调用点。

- [ ] **Step 3: 编译验证**

Run: `export DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer && make ios-build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 给 RecordComposerView 增加预填参数**

打开 `apps/ios/AimApp/Features/Records/RecordComposerView.swift`，把 `init` 改为：

```swift
    init(
        store: RecordStore,
        record: RecordItem? = nil,
        suggestedType: RecordType? = nil,
        suggestedText: String? = nil,
        onSaved: @escaping () -> Void
    ) {
        self.store = store
        self.record = record
        self.onSaved = onSaved
        let source = record
        _type = State(initialValue: source?.type ?? suggestedType)
        _occurredAt = State(initialValue: source?.occurredAt ?? .now)
        _visibility = State(initialValue: source?.visibility == .unknown ? .family : (source?.visibility ?? .family))
        if case let .symptom(data) = source?.structuredData {
            _symptoms = State(initialValue: Set(data.symptoms))
            _severity = State(initialValue: data.severity)
            _symptomNote = State(initialValue: data.note ?? "")
        } else {
            _symptoms = State(initialValue: [])
            _severity = State(initialValue: 1)
            _symptomNote = State(initialValue: "")
        }
        if case let .checkup(data) = source?.structuredData {
            _hospital = State(initialValue: data.hospital)
            _examItems = State(initialValue: data.examItems)
            _result = State(initialValue: data.result)
            _doctorAdvice = State(initialValue: data.doctorAdvice)
        } else {
            _hospital = State(initialValue: "")
            _examItems = State(initialValue: source?.title == nil && suggestedType == .checkup ? (suggestedText ?? "") : "")
            _result = State(initialValue: "")
            _doctorAdvice = State(initialValue: "")
        }
        _title = State(initialValue: source?.title ?? (suggestedType == .note ? (suggestedText ?? "") : ""))
        _content = State(initialValue: source?.content ?? "")
    }
```

注意 `_examItems` 的条件用 `source?.title == nil`（即没有传入已有记录）而不是重复判断 `record == nil` —— 两者等价（`source` 就是 `record`），这里直接复用已经在作用域里的 `source` 变量，避免多引入一次判断。

- [ ] **Step 5: 编译验证**

Run: `export DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer && make ios-build`
Expected: `** BUILD SUCCEEDED **`（现有两处调用点 `RecordComposerView(store:)`／`RecordComposerView(store:record:onSaved:)` 不传新参数，默认值保证行为不变）

- [ ] **Step 6: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): support prefilled record composer and toast identifiers"
```

---

### Task 3: TimelineStore.complete 报告成功与否

**Files:**
- Modify: `apps/ios/AimApp/Features/Timeline/TimelineStore.swift:112-120`
- Modify: `apps/ios/AimApp/Tests/TimelineStoreTests.swift`

**Interfaces:**
- Consumes: `BusinessRepositoryProtocol.complete(task:) async throws -> TaskItem`（已存在）
- Produces: `@discardableResult func complete(_ task: TaskItem) async -> Bool`

- [ ] **Step 1: 写失败测试**

在 `apps/ios/AimApp/Tests/TimelineStoreTests.swift` 末尾追加：

```swift
    func testCompleteWithoutRepositoryReturnsFalse() async {
        let store = TimelineStore()
        let task = TaskItem(id: UUID(), title: "核对材料", detail: nil, status: .todo, version: 1,
                             dueAt: nil, scheduledFor: nil, assignedMemberID: nil, changedByActor: .system)
        let result = await store.complete(task)
        XCTAssertFalse(result)
    }
```

- [ ] **Step 2: 运行测试确认失败**

Run: `export DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer && xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppTests/TimelineStoreTests`
Expected: 编译失败，`cannot convert return expression of type '()' to return type 'Bool'` 或类似（因为 `complete` 目前是 `Void`，测试里 `let result = await store.complete(task)` 会报无法赋值）

- [ ] **Step 3: 实现**

打开 `apps/ios/AimApp/Features/Timeline/TimelineStore.swift`，把：

```swift
    func complete(_ task: TaskItem) async {
        guard let repository else { return }
        do {
            _ = try await repository.complete(task: task)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

改为：

```swift
    @discardableResult
    func complete(_ task: TaskItem) async -> Bool {
        guard let repository else { return false }
        do {
            _ = try await repository.complete(task: task)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
```

- [ ] **Step 4: 运行测试确认通过**

Run: 同 Step 2 的命令
Expected: `testCompleteWithoutRepositoryReturnsFalse` 及其余既有 `TimelineStoreTests` 全部 PASS

- [ ] **Step 5: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): report task completion success from timeline store"
```

---

### Task 4: TimelineView 接入完成提示

**Files:**
- Modify: `apps/ios/AimApp/Features/Timeline/TimelineView.swift`

**Interfaces:**
- Consumes: `TimelineStore.complete(_:) async -> Bool`（Task 3）、`AimToastMessage(text:undoTitle:accessibilityIdentifier:undo:)`（Task 2）、`TaskRecordSuggestion.recordType(forTaskTitle:)`（Task 1）、`RecordComposerView.init(store:record:suggestedType:suggestedText:onSaved:)`（Task 2）
- Produces: `TimelineView` 新增 `@State private var recordPromptTask: TaskItem?`；任务行新增 `accessibilityIdentifier("timeline-task-row")`（供 Task 6 的 UI 测试定位，多行共享同一个标识符是合法用法）

- [ ] **Step 1: 加状态并接入滑动完成**

在 `TimelineView` 的 `@State` 声明区（`completedTaskID` 旁边）追加：

```swift
    @State private var recordPromptTask: TaskItem?
```

把滑动完成按钮的动作从：

```swift
                    Button {
                        Task {
                            await store.complete(task)
                            completedTaskID = task.id
                        }
                    } label: {
                        Label("完成", systemImage: "checkmark")
                    }
                    .tint(Color.aimSuccess)
```

改为：

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
                    } label: {
                        Label("完成", systemImage: "checkmark")
                    }
                    .tint(Color.aimSuccess)
```

- [ ] **Step 2: 给任务行加一个不依赖具体标题的可测试标识符**

任务行（`AimTaskRow`）目前没有任何和内容无关的 `accessibilityIdentifier`，而记录行已经有（`record-row-\(record.type.rawValue)`）。种子任务的标题依赖孕周和后端模板，UI 测试没法预先知道具体文案，需要一个稳定的定位方式。

在 `row(_ entry:)` 里 `.task` 分支的 `NavigationLink` 之后追加一行（多个任务行共享同一个标识符是合法的 XCUITest 用法，测试里用 `.firstMatch` 取第一个即可）：

```swift
        case let .task(task):
            NavigationLink {
                TaskDetailView(task: task, repository: planStore.repository)
            } label: {
                AimTaskRow(task: task, assigneeName: store.assigneeName(for: task.assignedMemberID))
            }
            .accessibilityIdentifier("timeline-task-row")
            .swipeActions(edge: .leading) {
```

（即在原有 `.swipeActions(edge: .leading) { ... }` 之前插入这一行 `.accessibilityIdentifier("timeline-task-row")`，`.swipeActions` 两段保持不变。）

- [ ] **Step 3: 加记录提示 sheet**

在 `.fullScreenCover(isPresented: $showingAgent) { ... }` 之后、`.aimToast($toast)` 之前追加：

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

- [ ] **Step 4: 编译验证**

Run: `export DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer && make ios-build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): prompt to add a record after completing a task on the timeline"
```

---

### Task 5: TaskDetailView 接入完成提示

**Files:**
- Modify: `apps/ios/AimApp/Features/TaskDetail/TaskDetailView.swift:1-63`

**Interfaces:**
- Consumes: `TaskDetailStore.complete() async -> Bool`（已存在，[TaskDetailStore.swift:17](apps/ios/AimApp/Features/TaskDetail/TaskDetailStore.swift:17)，无需改动）、`RecordStore`（`Features/Records/RecordStore.swift` 中已有）
- Produces: `TaskDetailView` 新增 `@State private var recordStore`、`@State private var recordPromptTask`、`@State private var toast`

- [ ] **Step 1: 加 RecordStore 并在初始化时接上 repository**

把 `TaskDetailView` 的属性与 `init` 从：

```swift
struct TaskDetailView: View {
    @State private var store: TaskDetailStore
    @State private var dueDate: Date
    @State private var showingDelay = false

    init(task: TaskItem, repository: BusinessRepositoryProtocol?) {
        _store = State(initialValue: TaskDetailStore(task: task, repository: repository))
        _dueDate = State(initialValue: task.dueAt ?? .now.addingTimeInterval(86_400))
    }
```

改为：

```swift
struct TaskDetailView: View {
    @State private var store: TaskDetailStore
    @State private var dueDate: Date
    @State private var showingDelay = false
    @State private var recordStore = RecordStore()
    @State private var recordPromptTask: TaskItem?
    @State private var toast: AimToastMessage?

    init(task: TaskItem, repository: BusinessRepositoryProtocol?) {
        _store = State(initialValue: TaskDetailStore(task: task, repository: repository))
        _dueDate = State(initialValue: task.dueAt ?? .now.addingTimeInterval(86_400))
        let records = RecordStore()
        records.repository = repository
        _recordStore = State(initialValue: records)
    }
```

- [ ] **Step 2: 接入「标记完成」按钮**

把：

```swift
            Section {
                Button {
                    Task {
                        _ = await store.complete()
                    }
                } label: {
                    Label(store.task.status == .completed ? "已完成" : "标记完成", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.task.status == .completed || store.isSaving)
            }
        }
        .navigationTitle("事项详情")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(isPresented: $showingDelay) {
            TaskDelaySheet(task: store.task, repository: store.repository) { updated in
                store.task = updated
            }
        }
    }
}
```

改为：

```swift
            Section {
                Button {
                    Task {
                        let task = store.task
                        if await store.complete() {
                            toast = AimToastMessage(
                                text: "已完成「\(task.title)」",
                                undoTitle: "记一下",
                                accessibilityIdentifier: "complete-task-record-prompt"
                            ) {
                                recordPromptTask = task
                            }
                        }
                    }
                } label: {
                    Label(store.task.status == .completed ? "已完成" : "标记完成", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.task.status == .completed || store.isSaving)
            }
        }
        .navigationTitle("事项详情")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(isPresented: $showingDelay) {
            TaskDelaySheet(task: store.task, repository: store.repository) { updated in
                store.task = updated
            }
        }
        .sheet(item: $recordPromptTask) { task in
            RecordComposerView(
                store: recordStore,
                suggestedType: TaskRecordSuggestion.recordType(forTaskTitle: task.title),
                suggestedText: task.title
            ) {
                recordPromptTask = nil
            }
        }
        .aimToast($toast)
    }
}
```

`let task = store.task` 在调用 `store.complete()` 之前捕获快照，是因为 `complete()` 成功后会把 `store.task.status` 改成 `.completed`——toast 文案要用完成前那一刻的标题（其实前后标题不变，但捕成功前的值语义更清楚，也避免未来 `complete()` 实现变化时产生竞态referencing 到已经变化的 `store.task`）。

- [ ] **Step 3: 编译验证**

Run: `export DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer && make ios-build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): prompt to add a record after completing a task from its detail view"
```

---

### Task 6: 端到端 UI 测试与全量验证

**Files:**
- Modify: `apps/ios/AimApp/UITests/CoreJourneyUITests.swift`

**Interfaces:**
- Consumes: `timeline-task-row`（Task 4）、`complete-task-record-prompt`（Task 4/5）

- [ ] **Step 1: 写 UI 测试**

在 `CoreJourneyUITests.swift` 末尾、`reveal(_:in:)` 之前追加：

```swift
    func testCompletingATaskOffersToRecordTheResult() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        if app.textFields["手机号"].waitForExistence(timeout: 2) {
            let phone = app.textFields["手机号"]
            phone.tap()
            phone.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
            phone.typeText("13800000002")
            app.buttons["开始体验"].tap()
        }

        let timelineTab = app.tabBars.buttons["孕期"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 8))
        timelineTab.tap()

        if app.buttons["补充孕期信息"].waitForExistence(timeout: 3) {
            app.buttons["补充孕期信息"].tap()
            app.buttons["保存并生成计划"].tap()
        }

        let taskRow = app.buttons.matching(identifier: "timeline-task-row").firstMatch
        XCTAssertTrue(taskRow.waitForExistence(timeout: 8))
        // .swipeActions(edge: .leading) 的「完成」按钮靠向右滑手势展开
        // （手指从左往右拖动内容，露出贴在左侧的 leading 按钮），不是 swipeLeft。
        taskRow.swipeRight()

        let completeAction = app.buttons["完成"]
        XCTAssertTrue(completeAction.waitForExistence(timeout: 3))
        completeAction.tap()

        let toast = app.otherElements["complete-task-record-prompt"]
        reveal(toast, in: app)

        app.buttons["记一下"].tap()

        XCTAssertTrue(app.navigationBars["新增记录"].waitForExistence(timeout: 3))
    }
```

若种子任务恰好没有可滑动的「完成」操作（例如已完成任务的行不显示滑动按钮，见 `TimelineView.row(_:)` 里 `if task.isOpen` 的判断），先确认 `timeline-task-row` 匹配到的第一行是否为未完成任务；`entries(in:)` 会把「现在最重要」那条任务排除在外，`.firstMatch` 拿到的是「接下来」列表里的第一条，正常情况下应为未完成状态。若测试运行后发现第一行恰好是已完成任务导致「完成」按钮不出现，改用 `app.buttons.matching(identifier: "timeline-task-row").element(boundBy: 1)` 或更靠后的索引重试，而不是假设固定就是第 0 个。

- [ ] **Step 2: 注册并跑通**

这个文件已经在 pbxproj 里注册过（`AimAppUITests` target），不需要新增文件引用。

Run: `export DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer && xcrun simctl shutdown all; xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppUITests/CoreJourneyUITests/testCompletingATaskOffersToRecordTheResult`
Expected: PASS

- [ ] **Step 3: 跑全量测试**

Run: `export DEVELOPER_DIR=/Users/hanbin/Downloads/Xcode.app/Contents/Developer && xcrun simctl shutdown all; make ios-test`
Expected: 全部单元测试 + 全部 UI 测试 PASS，无回归

- [ ] **Step 4: 提交**

```bash
git add apps/ios
git commit -m "test(ios): verify completing a task offers to record the result"
```

---

## 验收对照

对照规格 §10：

1. 完成任意任务后出现「记一下」提示，5 秒后自动消失 — Task 4/5（复用 `AimToast` 已有的 5 秒自动消失逻辑，未改动该部分）
2. 记录表单类型和文字已按任务标题预填、仍可修改 — Task 1（推断）+ Task 2（预填参数）+ `RecordComposerView` 原有的类型可切换逻辑（新建记录时 `.disabled(record != nil && candidate != type)` 对 `record == nil` 恒为 `false`，未受影响）
3. 任务完成失败不触发提示 — Task 3（`complete` 返回 `false` 时调用方不设置 toast）、Task 4/5 的 `if await store.complete(...)` 判断
4. 编辑已有记录入口不受影响 — Task 2 Step 4（`suggestedType`/`suggestedText` 只在 `source == nil` 分支生效）
