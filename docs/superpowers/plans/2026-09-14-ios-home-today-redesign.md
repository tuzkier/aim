# iOS 首页「今天」总控 + 时间线次级页 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 iOS「孕期」Tab 的首页从连续时间线改成以今天为顶的总控页，时间线降为从首页 push 进入的次级页，并补上手动新建待办的两种入口。

**Architecture:** `TimelineStore` 继续作为首页与时间线共享的数据源，只新增派生属性与 `createTask`。新建 `Features/Home/` 目录承载首页视图、头部、快速添加行、待办表单和相对日期文案；`TimelineView` 去掉头部与启动滚动，改为过去周折叠在顶部的次级页。数据层只给 `BusinessRepositoryProtocol` 加一个 `createTask`。

**Tech Stack:** SwiftUI（iOS 17 部署目标）、Observation、XCTest、XCUITest。工程文件是手写的 `project.pbxproj`（非 file-system-synchronized），新增 / 删除 / 移动源文件都要手工改 pbxproj。

规格：`docs/superpowers/specs/2026-09-14-ios-home-today-redesign-design.md`。

## Global Constraints

- 部署目标 iOS 17，不使用 iOS 18 才有的 API（如 `onScrollGeometryChange`）。
- 一律使用相对字体（`.body`、`.footnote` 等），禁止 `.system(size:)`。
- 颜色只用 `Color.aim*` token（`Core/DesignSystem/AimTheme.swift`），不新增 colorset。
- 间距与圆角只用 `AimMetrics` 常量。
- 陶土色 `aimAccent` 一屏最多四处；`aimDanger` 在首页只用于逾期标记。
- 文案为简体中文，与现有 UI 一致。
- 所有 sheet 内提交失败必须在 sheet 内可见；提交中按钮显示 loading 并禁用。
- 每个任务结束时 `make ios-parse`（仓库根目录）必须通过；涉及测试的任务运行对应测试。
- 提交信息格式沿用仓库习惯：`feat(ios): …` / `fix(ios): …` / `test(ios): …` / `refactor(ios): …`，中文描述。

## 命令速查

所有命令在仓库根目录 `/Users/hanbin/Workspace/AI/aim` 执行。

```bash
# 语法检查（秒级）
make ios-parse

# 只跑单元测试里的某个类（分钟级，首次编译较慢）
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO \
  -only-testing:AimAppTests/TimelineStoreTests test 2>&1 | tail -30

# 全部单元测试（不含 UI 测试）
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO \
  -only-testing:AimAppTests test 2>&1 | tail -30

# UI 测试需要本地栈：先在另一个终端 make dev
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO \
  -only-testing:AimAppUITests test 2>&1 | tail -30
```

`xcodebuild` 输出很长，看末尾的 `** TEST SUCCEEDED **` / `** TEST FAILED **` 和 `Executed N tests, with M failures`。

## pbxproj 约定

`apps/ios/AimApp.xcodeproj/project.pbxproj` 里每个源文件需要四处条目：

1. `PBXBuildFile` 段（文件开头，形如 `A2… /* path in Sources */ = {isa = PBXBuildFile; fileRef = A1… /* path */; };`）
2. `PBXFileReference` 段（`A1… /* path */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = path; sourceTree = "<group>"; };`）
3. 所属 `PBXGroup` 的 `children` 列表（引用 `A1…`）
4. 目标的 `PBXSourcesBuildPhase` 的 `files` 列表（引用 `A2…`）：App 目标是 `A30000000000000000000004 /* Sources */`，单元测试目标是 `A30000000000000000000006 /* Sources */`

当前已用的最大编号是 `…0131`。本计划分配：

| 文件 | fileRef | buildFile |
| --- | --- | --- |
| `Features/Home/HomeView.swift` | `A10000000000000000000132` | `A20000000000000000000132` |
| `Features/Home/TaskQuickAddRow.swift` | `A10000000000000000000133` | `A20000000000000000000133` |
| `Features/Home/TaskComposerView.swift` | `A10000000000000000000134` | `A20000000000000000000134` |
| `Features/Home/TaskDateText.swift` | `A10000000000000000000135` | `A20000000000000000000135` |
| `Tests/TaskDateTextTests.swift` | `A10000000000000000000136` | `A20000000000000000000136` |
| `Tests/TaskComposerViewTests.swift` | `A10000000000000000000137` | `A20000000000000000000137` |
| 新分组 `Home` | `A40000000000000000000106` | — |

改名 / 移动的文件保留原编号，只改 `path` 和所属分组：`TimelineHeader.swift`（`A1…0057` / `A2…0058`）→ `Features/Home/HomeHeader.swift`；`Features/Today/TodayView.swift`（`A1…0022` / `A2…0022`）→ `Features/Onboarding/PregnancySetupView.swift`。

---

### Task 1: 相对日期文案 `TaskDateText`

**Files:**
- Create: `apps/ios/AimApp/Features/Home/TaskDateText.swift`
- Create: `apps/ios/AimApp/Tests/TaskDateTextTests.swift`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces:
  - `enum TaskDateText`
  - `static func endOfDay(_ date: Date, calendar: Calendar = PregnancyDateCalculator.calendar) -> Date` — 返回当天 23:59:00
  - `static func isEndOfDaySentinel(_ date: Date, calendar: Calendar = PregnancyDateCalculator.calendar) -> Bool`
  - `static func label(for date: Date, now: Date, calendar: Calendar = PregnancyDateCalculator.calendar) -> String`

- [ ] **Step 1: 在 pbxproj 里登记两个新文件和 Home 分组**

在 `PBXBuildFile` 段末尾（`/* End PBXBuildFile section */` 之前）追加：

```
		A20000000000000000000135 /* Features/Home/TaskDateText.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10000000000000000000135 /* Features/Home/TaskDateText.swift */; };
		A20000000000000000000136 /* Tests/TaskDateTextTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10000000000000000000136 /* Tests/TaskDateTextTests.swift */; };
```

在 `PBXFileReference` 段末尾追加：

```
		A10000000000000000000135 /* Features/Home/TaskDateText.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Features/Home/TaskDateText.swift; sourceTree = "<group>"; };
		A10000000000000000000136 /* Tests/TaskDateTextTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/TaskDateTextTests.swift; sourceTree = "<group>"; };
```

在 `PBXGroup` 段，紧跟 `A40000000000000000000103 /* Timeline */` 分组定义之后新增分组：

```
		A40000000000000000000106 /* Home */ = {
			isa = PBXGroup;
			children = (
				A10000000000000000000135 /* Features/Home/TaskDateText.swift */,
			);
			name = Home;
			sourceTree = "<group>";
		};
```

找到引用 `A40000000000000000000103 /* Timeline */,` 的那个 children 列表（约第 384 行），在它下一行加 `A40000000000000000000106 /* Home */,`。

在 `A40000000000000000000014 /* Tests */` 分组的 children 里加 `A10000000000000000000136 /* Tests/TaskDateTextTests.swift */,`。

在 `A30000000000000000000004 /* Sources */` 的 files 里加 `A20000000000000000000135 /* Features/Home/TaskDateText.swift in Sources */,`；在 `A30000000000000000000006 /* Sources */` 的 files 里加 `A20000000000000000000136 /* Tests/TaskDateTextTests.swift in Sources */,`。

- [ ] **Step 2: 写失败的测试**

`apps/ios/AimApp/Tests/TaskDateTextTests.swift`：

```swift
import XCTest
@testable import AimApp

final class TaskDateTextTests: XCTestCase {
    private let calendar = PregnancyDateCalculator.calendar

    /// 2026-09-14 是周一。
    private let now = PregnancyDateCalculator.calendar.date(
        from: DateComponents(year: 2026, month: 9, day: 14, hour: 10, minute: 30))!

    private func at(_ day: Int, _ hour: Int = 9, _ minute: Int = 0, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func testTodayTomorrowYesterday() {
        XCTAssertEqual(TaskDateText.label(for: at(14, 19, 30), now: now), "今天 19:30")
        XCTAssertEqual(TaskDateText.label(for: at(15, 8), now: now), "明天 08:00")
        XCTAssertEqual(TaskDateText.label(for: at(13, 20), now: now), "昨天 20:00")
    }

    func testWithinAWeekUsesWeekday() {
        XCTAssertEqual(TaskDateText.label(for: at(16, 9), now: now), "周三 09:00")
        XCTAssertEqual(TaskDateText.label(for: at(20, 9), now: now), "周日 09:00")
    }

    func testSevenDaysOrMoreUsesCalendarDate() {
        XCTAssertEqual(TaskDateText.label(for: at(21, 9), now: now), "9月21日 09:00")
        XCTAssertEqual(TaskDateText.label(for: at(2, 9, month: 10), now: now), "10月2日 09:00")
    }

    func testPastDaysCountBackUpToAWeek() {
        XCTAssertEqual(TaskDateText.label(for: at(11, 9), now: now), "3 天前 09:00")
        XCTAssertEqual(TaskDateText.label(for: at(7, 9), now: now), "7 天前 09:00")
        XCTAssertEqual(TaskDateText.label(for: at(6, 9), now: now), "9月6日 09:00")
    }

    func testEndOfDaySentinelHidesTime() {
        let due = TaskDateText.endOfDay(at(14))
        XCTAssertTrue(TaskDateText.isEndOfDaySentinel(due))
        XCTAssertEqual(TaskDateText.label(for: due, now: now), "今天")
        XCTAssertFalse(TaskDateText.isEndOfDaySentinel(at(14, 23, 58)))
    }

    func testEndOfDayIsTwentyThreeFiftyNine() {
        let components = calendar.dateComponents([.hour, .minute, .second], from: TaskDateText.endOfDay(at(14, 3)))
        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 59)
        XCTAssertEqual(components.second, 0)
    }
}
```

- [ ] **Step 3: 跑测试确认编译失败**

```bash
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests/TaskDateTextTests test 2>&1 | grep -E "error:|TEST" | head
```

预期：`error: cannot find 'TaskDateText' in scope`。

- [ ] **Step 4: 实现**

`apps/ios/AimApp/Features/Home/TaskDateText.swift`：

```swift
import Foundation

/// 任务行元信息里的相对日期。首页和时间线共用，保证同一个截止时间在两处显示一致。
///
/// 快速添加的待办没有让用户选时刻，截止时间统一落在当天 23:59；这个时刻是哨兵值，
/// 显示时把它藏掉——用户看到「今天」就够了，「今天 23:59」反而像个真实的 deadline。
enum TaskDateText {
    static func endOfDay(_ date: Date, calendar: Calendar = PregnancyDateCalculator.calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: start) ?? start
    }

    static func isEndOfDaySentinel(_ date: Date, calendar: Calendar = PregnancyDateCalculator.calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return parts.hour == 23 && parts.minute == 59
    }

    static func label(for date: Date, now: Date, calendar: Calendar = PregnancyDateCalculator.calendar) -> String {
        let dayDiff = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0

        let day: String
        switch dayDiff {
        case 0: day = "今天"
        case 1: day = "明天"
        case -1: day = "昨天"
        case 2...6: day = format(date, "EEE", calendar: calendar)
        case -7 ... -2: day = "\(-dayDiff) 天前"
        default: day = format(date, "M月d日", calendar: calendar)
        }

        guard !isEndOfDaySentinel(date, calendar: calendar) else { return day }
        return day + " " + format(date, "HH:mm", calendar: calendar)
    }

    private static func format(_ date: Date, _ pattern: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

同 Step 3 的命令。预期：`Executed 6 tests, with 0 failures`。若 `EEE` 输出的是「星期三」而不是「周三」，把 `case 2...6` 改为 `"周" + ["日","一","二","三","四","五","六"][calendar.component(.weekday, from: date) - 1]`，删掉对 `EEE` 的依赖，再跑一次。

- [ ] **Step 6: 提交**

```bash
git add apps/ios/AimApp/Features/Home/TaskDateText.swift apps/ios/AimApp/Tests/TaskDateTextTests.swift apps/ios/AimApp.xcodeproj/project.pbxproj
git commit -m "feat(ios): 任务行的相对日期文案"
```

---

### Task 2: 数据层 `createTask`

**Files:**
- Modify: `apps/ios/AimApp/Clients/BusinessAPIClient/BusinessRepository.swift`（协议约第 111–130 行；`createTaskFromRecord` 约第 254 行；`CreateTaskFromRecordBody` 约第 405 行）
- Modify: `apps/ios/AimApp/Tests/BusinessRepositoryTests.swift`
- Modify: `apps/ios/AimApp/Tests/LibraryStoreTests.swift`（`FakeLibraryRepository`、`CountingRepository`、`DeletingRepository`）
- Modify: `apps/ios/AimApp/Tests/AgentActivityLogTests.swift`（`SpyRepository`）
- Modify: `apps/ios/AimApp/Tests/RecordStoreTests.swift`（`FailingRecordRepository`）

**Interfaces:**
- Produces:
  - `BusinessRepositoryProtocol.createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem`
  - `struct CreateTaskBody: Encodable`（internal，供测试编码）

- [ ] **Step 1: 写失败的编码测试**

在 `Tests/BusinessRepositoryTests.swift` 的类里追加：

```swift
    func testCreateTaskBodyUsesSnakeCaseAndOmitsNothingRequired() throws {
        let memberID = UUID()
        let due = Date(timeIntervalSince1970: 1_790_000_000)
        let body = CreateTaskBody(title: "买叶酸", description: "药店", dueAt: due, assignedMemberID: memberID, recordID: nil, sourceType: nil)
        let data = try JSONEncoder.aim.encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["title"] as? String, "买叶酸")
        XCTAssertEqual(json["description"] as? String, "药店")
        XCTAssertEqual(json["assigned_member_id"] as? String, memberID.uuidString)
        XCTAssertNotNil(json["due_at"])
        XCTAssertNil(json["record_id"], "手动新建不带记录")
        XCTAssertNil(json["source_type"], "留给服务端默认的 user")
    }

    func testCreateTaskFromRecordBodyKeepsRecordSource() throws {
        let recordID = UUID()
        let body = CreateTaskBody(title: "复查", description: nil, dueAt: nil, assignedMemberID: nil, recordID: recordID, sourceType: "record")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.aim.encode(body)) as? [String: Any])
        XCTAssertEqual(json["record_id"] as? String, recordID.uuidString)
        XCTAssertEqual(json["source_type"] as? String, "record")
    }
```

- [ ] **Step 2: 跑测试确认编译失败**

```bash
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests/BusinessRepositoryTests test 2>&1 | grep -E "error:|TEST" | head
```

预期：`cannot find 'CreateTaskBody' in scope`。

- [ ] **Step 3: 实现协议方法与通用 body**

在 `BusinessRepository.swift` 把 `private struct CreateTaskFromRecordBody` 整段替换为：

```swift
struct CreateTaskBody: Encodable {
    let title: String
    let description: String?
    let dueAt: Date?
    let assignedMemberID: UUID?
    let recordID: UUID?
    /// nil 时不发这个字段，服务端默认 `user`。
    let sourceType: String?

    enum CodingKeys: String, CodingKey {
        case title, description
        case dueAt = "due_at"
        case assignedMemberID = "assigned_member_id"
        case recordID = "record_id"
        case sourceType = "source_type"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(dueAt, forKey: .dueAt)
        try container.encodeIfPresent(assignedMemberID, forKey: .assignedMemberID)
        try container.encodeIfPresent(recordID, forKey: .recordID)
        try container.encodeIfPresent(sourceType, forKey: .sourceType)
    }
}
```

在协议里 `createTaskFromRecord` 一行之后加：

```swift
    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem
```

把 actor 里的 `createTaskFromRecord` 改为，并在其后加 `createTask`：

```swift
    func createTaskFromRecord(record: RecordItem, title: String, description: String?, dueAt: Date?) async throws -> TaskItem {
        let pregnancyID = try requiredPregnancyID()
        guard record.pregnancyID == pregnancyID else { throw APIError.invalidResponse }
        return try await postTask(CreateTaskBody(
            title: title, description: description, dueAt: dueAt,
            assignedMemberID: nil, recordID: record.id, sourceType: "record"))
    }

    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem {
        try await postTask(CreateTaskBody(
            title: title, description: description, dueAt: dueAt,
            assignedMemberID: assignedMemberID, recordID: nil, sourceType: nil))
    }

    private func postTask(_ body: CreateTaskBody) async throws -> TaskItem {
        let pregnancyID = try requiredPregnancyID()
        let request = environment.businessRequest(
            path: "/api/v1/pregnancies/\(pregnancyID.uuidString)/tasks",
            method: "POST",
            body: try encoder.encode(body)
        )
        let (data, _) = try await session.aimData(for: request)
        return map(try decoder.decode(APITaskDTO.self, from: data))
    }
```

- [ ] **Step 4: 给测试替身补方法**

在以下每个类型里，紧跟其 `createTaskFromRecord` 方法之后加一行：

- `Tests/LibraryStoreTests.swift` 的 `FakeLibraryRepository`、`CountingRepository`、`DeletingRepository`
- `Tests/AgentActivityLogTests.swift` 的 `SpyRepository`
- `Tests/RecordStoreTests.swift` 的 `FailingRecordRepository`

```swift
    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem { throw APIError.notConfigured }
```

`FailingRecordRepository` 里其它方法抛的是 `APIError.invalidResponse`，那里也用 `invalidResponse` 保持一致。

- [ ] **Step 5: 语法检查 + 跑测试**

```bash
make ios-parse
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests/BusinessRepositoryTests -only-testing:AimAppTests/LibraryStoreTests -only-testing:AimAppTests/AgentActivityLogTests -only-testing:AimAppTests/RecordStoreTests test 2>&1 | grep -E "error:|Executed|TEST" | tail
```

预期：全部通过，`with 0 failures`。

- [ ] **Step 6: 提交**

```bash
git add apps/ios/AimApp/Clients/BusinessAPIClient/BusinessRepository.swift apps/ios/AimApp/Tests
git commit -m "feat(ios): 仓储层支持手动新建待办"
```

---

### Task 3: `TimelineStore` 首页派生属性与 `createTask`

**Files:**
- Modify: `apps/ios/AimApp/Features/Timeline/TimelineStore.swift`
- Modify: `apps/ios/AimApp/Tests/TimelineStoreTests.swift`

**Interfaces:**
- Consumes: `TaskDateText.endOfDay`（Task 1）、`BusinessRepositoryProtocol.createTask`（Task 2）
- Produces（全部在 `TimelineStore` 上）:
  - `var now: Date`（`load()` 时刷新为 `.now`，测试可注入）
  - `var stageName: String?` — 孕早期 / 孕中期 / 孕晚期
  - `var focusTask: TaskItem?` — 新规则（替换旧实现）
  - `var todayTasks: [TaskItem]`
  - `var overdueCount: Int`
  - `func isOverdue(_ task: TaskItem) -> Bool`
  - `var upcomingTasks: [TaskItem]`
  - `var recentRecords: [RecordItem]`
  - `var pastWeeks: [TimelineWeek]`
  - `var isPastExpanded: Bool`
  - `@discardableResult func createTask(title: String, description: String? = nil, dueAt: Date?, assignedMemberID: UUID? = nil) async -> Bool`

- [ ] **Step 1: 写失败的测试**

把 `Tests/TimelineStoreTests.swift` 里的 `testFocusTaskPrefersEarliestOpenTaskInCurrentWeek` 删掉，追加以下测试与替身。文件顶部已有 `import XCTest` / `@testable import AimApp` / `@MainActor final class TimelineStoreTests`。

```swift
    // MARK: - 首页派生属性

    private let calendar = PregnancyDateCalculator.calendar

    /// 2026-09-14 周一 10:30，孕 22 周 + 6 天。
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 10, minute: 30))!
    }

    private func at(_ day: Int, _ hour: Int = 9, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func task(_ title: String, due: Date?, status: TaskStatus = .todo) -> TaskItem {
        TaskItem(id: UUID(), title: title, detail: nil, status: status, version: 1,
                 dueAt: due, scheduledFor: nil, assignedMemberID: nil, changedByActor: .system)
    }

    private func record(_ occurred: Date, title: String) -> RecordItem {
        RecordItem(id: UUID(), pregnancyID: UUID(), familyID: UUID(), authorAccountID: UUID(),
                   type: .note, occurredAt: occurred, visibility: .family, title: title, content: nil,
                   structuredData: .note, attachmentRefs: [], createdAt: occurred, updatedAt: occurred)
    }

    private func makeStore(tasks: [TaskItem], records: [RecordItem] = [], weeks: Int = 22, days: Int = 6) -> TimelineStore {
        let store = TimelineStore()
        store.now = now
        store.today = now
        store.tasks = tasks
        store.records = records
        store.lastMenstrualPeriod = TimelineBuilder.lastMenstrualPeriod(asOf: now, weeks: weeks, days: days)
        store.rebuild()
        return store
    }

    func testStageNameFollowsWeek() {
        XCTAssertEqual(makeStore(tasks: [], weeks: 13, days: 6).stageName, "孕早期")
        XCTAssertEqual(makeStore(tasks: [], weeks: 14, days: 0).stageName, "孕中期")
        XCTAssertEqual(makeStore(tasks: [], weeks: 27, days: 6).stageName, "孕中期")
        XCTAssertEqual(makeStore(tasks: [], weeks: 28, days: 0).stageName, "孕晚期")
    }

    func testFocusPrefersOverdueThenTodayThenEarliestUpcoming() {
        let overdue = task("逾期", due: at(12))
        let today = task("今天", due: at(14, 20))
        let later = task("下周", due: at(20))
        XCTAssertEqual(makeStore(tasks: [later, today, overdue]).focusTask?.title, "逾期")
        XCTAssertEqual(makeStore(tasks: [later, today]).focusTask?.title, "今天")
        XCTAssertEqual(makeStore(tasks: [later]).focusTask?.title, "下周")
        XCTAssertNil(makeStore(tasks: [task("完了", due: at(14), status: .completed)]).focusTask)
    }

    func testTodayTasksIncludeOverdueAndUndatedButExcludeFocus() {
        let overdue = task("逾期", due: at(12))
        let today = task("今天", due: at(14, 20))
        let undated = task("没定时间", due: nil)
        let done = task("已完成", due: at(14), status: .completed)
        let tomorrow = task("明天", due: at(15))
        let store = makeStore(tasks: [undated, tomorrow, today, done, overdue])

        XCTAssertEqual(store.focusTask?.title, "逾期")
        XCTAssertEqual(store.todayTasks.map(\.title), ["今天", "没定时间"])
        XCTAssertEqual(store.overdueCount, 0, "逾期的那条已经是焦点，不重复计")
        XCTAssertTrue(store.isOverdue(overdue))
        XCTAssertFalse(store.isOverdue(today))
    }

    func testOverdueCountCountsOverdueRowsInTodayGroup() {
        let a = task("逾期 A", due: at(10))
        let b = task("逾期 B", due: at(12))
        let store = makeStore(tasks: [b, a])
        XCTAssertEqual(store.focusTask?.title, "逾期 A")
        XCTAssertEqual(store.todayTasks.map(\.title), ["逾期 B"])
        XCTAssertEqual(store.overdueCount, 1)
    }

    func testUpcomingCoversTomorrowThroughSeventhDay() {
        let tomorrow = task("明天", due: at(15))
        let seventh = task("第七天", due: at(21, 23))
        let eighth = task("第八天", due: at(22))
        let today = task("今天", due: at(14, 20))
        let store = makeStore(tasks: [eighth, seventh, tomorrow, today])
        XCTAssertEqual(store.upcomingTasks.map(\.title), ["明天", "第七天"])
    }

    func testRecentRecordsTakesLatestThree() {
        let store = makeStore(tasks: [], records: [
            record(at(1), title: "一"), record(at(10), title: "十"),
            record(at(5), title: "五"), record(at(13), title: "十三"),
        ])
        XCTAssertEqual(store.recentRecords.map(\.title), ["十三", "十", "五"])
    }

    func testPastWeeksExcludeCurrentAndFuture() {
        let store = makeStore(tasks: [
            task("上上周", due: at(1), status: .completed),
            task("今天", due: at(14)),
            task("下周", due: at(22)),
        ])
        XCTAssertEqual(store.pastWeeks.map(\.week), [20])
        XCTAssertFalse(store.isPastExpanded)
    }

    func testCreateTaskReloadsOnSuccessAndReportsFailure() async {
        let repository = StubTimelineRepository()
        let store = TimelineStore()
        store.repository = repository

        let ok = await store.createTask(title: "买叶酸", dueAt: nil)
        XCTAssertTrue(ok)
        XCTAssertEqual(repository.createdTitles, ["买叶酸"])
        XCTAssertEqual(repository.fetchPlanCount, 1, "成功后要 reload")

        repository.shouldFail = true
        let failed = await store.createTask(title: "再来", dueAt: nil)
        XCTAssertFalse(failed)
        XCTAssertNotNil(store.errorMessage)
    }
```

在文件末尾（类外）加替身：

```swift
private final class StubTimelineRepository: BusinessRepositoryProtocol, @unchecked Sendable {
    var createdTitles: [String] = []
    var fetchPlanCount = 0
    var shouldFail = false

    private let today = PregnancyDateCalculator.calendar.date(
        from: DateComponents(year: 2026, month: 9, day: 14, hour: 9))!

    func createTask(title: String, description: String?, dueAt: Date?, assignedMemberID: UUID?) async throws -> TaskItem {
        if shouldFail { throw APIError.invalidResponse }
        createdTitles.append(title)
        return TaskItem(id: UUID(), title: title, detail: description, status: .todo, version: 1,
                        dueAt: dueAt, scheduledFor: nil, assignedMemberID: assignedMemberID, changedByActor: .account)
    }

    func fetchToday() async throws -> TodaySnapshot {
        TodaySnapshot(pregnancyID: UUID(), asOf: today, weeks: 22, days: 6, priorityTask: nil, upcomingTasks: [], familyOpenTaskCount: 0)
    }
    func fetchPlan() async throws -> PlanSnapshot {
        fetchPlanCount += 1
        return PlanSnapshot(id: UUID(), pregnancyID: UUID(), version: 1, tasks: [])
    }
    func fetchFamily() async throws -> FamilySnapshot { FamilySnapshot(id: UUID(), name: "家", members: []) }
    func fetchRecords(type: RecordType?) async throws -> RecordSnapshot { RecordSnapshot(records: []) }
    func createPregnancy(dueDate: Date) async throws -> UUID { throw APIError.notConfigured }
    func createRecord(draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func updateRecord(recordID: UUID, draft: RecordDraft) async throws -> RecordItem { throw APIError.notConfigured }
    func deleteRecord(recordID: UUID) async throws { throw APIError.notConfigured }
    func deleteTask(taskID: UUID) async throws { throw APIError.notConfigured }
    func fetchSafetyRules() async throws -> [SafetyRule] { [] }
    func fetchContentCollection(_ name: String) async throws -> ContentCollection {
        ContentCollection(id: name, source: "test", sourceURL: "", items: [])
    }
    func createTaskFromRecord(record: RecordItem, title: String, description: String?, dueAt: Date?) async throws -> TaskItem { throw APIError.notConfigured }
    func complete(task: TaskItem) async throws -> TaskItem { throw APIError.notConfigured }
    func delay(task: TaskItem, until: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func schedule(task: TaskItem, at: Date) async throws -> TaskItem { throw APIError.notConfigured }
    func assign(task: TaskItem, to memberID: UUID?) async throws -> TaskItem { throw APIError.notConfigured }
    func invite(phone: String, role: FamilyRole) async throws { throw APIError.notConfigured }
    func renameFamily(to name: String) async throws {}
    func updateMyMembership(nickname: String?, role: FamilyRole?) async throws {}
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests/TimelineStoreTests test 2>&1 | grep -E "error:|TEST" | head
```

预期：`value of type 'TimelineStore' has no member 'now'` 之类的编译错误。

- [ ] **Step 3: 实现**

在 `TimelineStore.swift` 里：

（a）属性区 `var currentDays: Int = 0` 之后加：

```swift
    /// 首页各分组的「现在」。与 `today`（服务端 as_of，用于孕周换算）分开：
    /// as_of 是日期不是时刻，用它判断「今天 20:00 是否已过」会出错。
    var now: Date = .now

    var isPastExpanded = false
```

（b）`load()` 里 `today = todaySnapshot.asOf` 之前加 `now = .now`。

（c）把旧的 `var focusTask: TaskItem?` 整段替换为下面这组：

```swift
    // MARK: - 首页派生

    var stageName: String? {
        guard let week = currentWeek else { return nil }
        if week <= 13 { return "孕早期" }
        if week <= 27 { return "孕中期" }
        return "孕晚期"
    }

    private var endOfToday: Date { TaskDateText.endOfDay(now) }
    private var startOfToday: Date { TimelineBuilder.calendar.startOfDay(for: now) }

    /// 未完成任务按截止时间升序，没有截止时间的排最后。
    private var openTasksByDue: [TaskItem] {
        tasks.filter(\.isOpen).sorted { lhs, rhs in
            switch (lhs.dueAt, rhs.dueAt) {
            case let (l?, r?): return l < r
            case (nil, nil): return lhs.id.uuidString < rhs.id.uuidString
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }

    /// 逾期或今天截止的最早一条；没有就是所有未完成里最早的；都没有就不显示焦点卡。
    var focusTask: TaskItem? {
        let open = openTasksByDue
        if let dueSoon = open.first(where: { ($0.dueAt ?? .distantFuture) <= endOfToday }) { return dueSoon }
        return open.first
    }

    func isOverdue(_ task: TaskItem) -> Bool {
        guard let due = task.dueAt else { return false }
        return due < startOfToday
    }

    /// 今天组：截止 ≤ 今天 23:59 或没有截止时间，排除焦点任务。逾期自然排在最前。
    var todayTasks: [TaskItem] {
        let focusID = focusTask?.id
        return openTasksByDue.filter { task in
            task.id != focusID && (task.dueAt.map { $0 <= endOfToday } ?? true)
        }
    }

    var overdueCount: Int { todayTasks.filter(isOverdue).count }

    /// 接下来 7 天：明天 00:00 到第 7 天 23:59。
    var upcomingTasks: [TaskItem] {
        let focusID = focusTask?.id
        guard let seventh = TimelineBuilder.calendar.date(byAdding: .day, value: 7, to: startOfToday) else { return [] }
        let windowEnd = TaskDateText.endOfDay(seventh)
        return openTasksByDue.filter { task in
            guard task.id != focusID, let due = task.dueAt else { return false }
            return due > endOfToday && due <= windowEnd
        }
    }

    var recentRecords: [RecordItem] {
        Array(records.sorted { $0.occurredAt > $1.occurredAt }.prefix(3))
    }

    var pastWeeks: [TimelineWeek] { weeks.filter { $0.position == .past } }

    @discardableResult
    func createTask(title: String, description: String? = nil, dueAt: Date?, assignedMemberID: UUID? = nil) async -> Bool {
        guard let repository else { return false }
        do {
            _ = try await repository.createTask(
                title: title, description: description, dueAt: dueAt, assignedMemberID: assignedMemberID)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
```

注意 `upcomingTasks` 里 `seventh` 是「今天 + 7 天」的 00:00，`endOfDay(seventh)` 即第 7 天 23:59，与测试 `at(21, 23)` 命中、`at(22)` 落空一致。

- [ ] **Step 4: 跑测试确认通过**

同 Step 2 命令。预期 `with 0 failures`。`testAssigneeNameResolvesFromFamilyMembers`、`testCompleteWithoutRepositoryReturnsFalse` 和三个 filter 测试仍应通过。

- [ ] **Step 5: 提交**

```bash
git add apps/ios/AimApp/Features/Timeline/TimelineStore.swift apps/ios/AimApp/Tests/TimelineStoreTests.swift
git commit -m "feat(ios): 首页分组所需的派生属性与新建待办"
```

---

### Task 4: `AimTaskRow` 支持行内勾选、请求中态、虚线圆与相对日期

**Files:**
- Modify: `apps/ios/AimApp/Core/DesignSystem/Components/AimTimelineRows.swift`（`AimTaskRow`，约第 10–78 行）

**Interfaces:**
- Consumes: `TaskDateText.label(for:now:)`
- Produces: `AimTaskRow(task:assigneeName:now:isOverdue:isPending:style:onToggle:)`，其中 `enum Style { case due, upcoming }`

- [ ] **Step 1: 替换 `AimTaskRow`**

把 `struct AimTaskRow` 整段替换为：

```swift
struct AimTaskRow: View {
    enum Style { case due, upcoming }

    let task: TaskItem
    var assigneeName: String?
    var now: Date = .now
    var isOverdue = false
    var isPending = false
    var style: Style = .due
    var onToggle: (() -> Void)?

    private var isDone: Bool { task.status == .completed }

    var body: some View {
        HStack(alignment: .top, spacing: AimMetrics.space12) {
            Button { onToggle?() } label: { checkbox }
                .buttonStyle(.plain)
                .disabled(onToggle == nil || isPending || isDone)
                .accessibilityLabel(isDone ? "已完成" : "标记完成")
                .accessibilityIdentifier("home-task-checkbox")

            VStack(alignment: .leading, spacing: AimMetrics.space4) {
                Text(task.title)
                    .font(.body)
                    .foregroundStyle(isDone ? Color.aimTextTertiary : Color.aimTextPrimary)
                    .strikethrough(isDone, color: Color.aimTextTertiary)
                meta
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AimMetrics.space8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var checkbox: some View {
        if isPending {
            ProgressView()
                .controlSize(.small)
                .frame(width: AimMetrics.checkboxSize, height: AimMetrics.checkboxSize)
        } else if isDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(Color.aimSuccess)
        } else if style == .upcoming {
            Circle()
                .stroke(Color.aimRail, style: StrokeStyle(lineWidth: AimMetrics.railDotStroke, dash: [2, 2]))
                .frame(width: AimMetrics.checkboxSize, height: AimMetrics.checkboxSize)
        } else {
            Circle()
                .stroke(Color.aimRail, lineWidth: AimMetrics.railDotStroke)
                .frame(width: AimMetrics.checkboxSize, height: AimMetrics.checkboxSize)
        }
    }

    @ViewBuilder
    private var meta: some View {
        let parts = metaParts
        if !parts.isEmpty || isOverdue || task.isAgentChanged {
            HStack(spacing: AimMetrics.space4) {
                if isOverdue {
                    Text("逾期")
                        .font(.footnote)
                        .foregroundStyle(Color.aimDanger)
                    if !parts.isEmpty { separator }
                }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Color.aimTextSecondary)
                }
                if task.isAgentChanged {
                    if isOverdue || !parts.isEmpty { separator }
                    AimSourceBadge()
                }
            }
        }
    }

    private var separator: some View {
        Text("·").font(.footnote).foregroundStyle(Color.aimTextSecondary)
    }

    private var metaParts: [String] {
        var parts: [String] = []
        if let assigneeName { parts.append(assigneeName) }
        if let date = task.dueAt ?? task.scheduledFor {
            parts.append(TaskDateText.label(for: date, now: now))
        }
        return parts
    }
}
```

- [ ] **Step 2: 语法检查**

```bash
make ios-parse
```

预期无输出（成功）。`TimelineView` 仍以 `AimTaskRow(task:assigneeName:)` 调用，新参数都有默认值，不需要改。

- [ ] **Step 3: 提交**

```bash
git add apps/ios/AimApp/Core/DesignSystem/Components/AimTimelineRows.swift
git commit -m "feat(ios): 任务行支持行内勾选、请求中态与相对日期"
```

---

### Task 5: 快速添加行 `TaskQuickAddRow`

**Files:**
- Create: `apps/ios/AimApp/Features/Home/TaskQuickAddRow.swift`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `TaskQuickAddRow(isEditing: Binding<Bool>, text: Binding<String>, isSubmitting: Bool, errorMessage: String?, onSubmit: () -> Void)`

- [ ] **Step 1: 登记 pbxproj**

按「pbxproj 约定」为 `Features/Home/TaskQuickAddRow.swift` 加四处条目：`PBXBuildFile` 用 `A20000000000000000000133`，`PBXFileReference` 用 `A10000000000000000000133`，加进 `A40000000000000000000106 /* Home */` 的 children 和 `A30000000000000000000004 /* Sources */` 的 files。

- [ ] **Step 2: 实现**

```swift
import SwiftUI

/// 今天组最后一行：平时是一行灰字「添加待办」，点开变成输入框。
///
/// 成功后不收起、不失焦——连着记几条是常态。失败时错误显示在本行下面，
/// 输入保留，用户改一改再回车即可，不用重新打字。
struct TaskQuickAddRow: View {
    @Binding var isEditing: Bool
    @Binding var text: String
    let isSubmitting: Bool
    let errorMessage: String?
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space4) {
            HStack(spacing: AimMetrics.space12) {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: AimMetrics.checkboxSize, height: AimMetrics.checkboxSize)
                } else {
                    Image(systemName: "plus")
                        .font(.body)
                        .foregroundStyle(Color.aimTextTertiary)
                        .frame(width: AimMetrics.checkboxSize)
                }

                if isEditing {
                    TextField("要做什么", text: $text)
                        .font(.body)
                        .foregroundStyle(Color.aimTextPrimary)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(onSubmit)
                        .disabled(isSubmitting)
                        .accessibilityLabel("添加待办")
                        .accessibilityIdentifier("home-quick-add-field")
                } else {
                    Button {
                        isEditing = true
                    } label: {
                        Text("添加待办")
                            .font(.body)
                            .foregroundStyle(Color.aimTextTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home-quick-add")
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.aimDanger)
                    .padding(.leading, AimMetrics.checkboxSize + AimMetrics.space12)
            }
        }
        .padding(.vertical, AimMetrics.space8)
        .onChange(of: isEditing) { _, editing in
            isFocused = editing
        }
        .onChange(of: isFocused) { _, focused in
            // 失焦且没在提交、也没输入内容时收起；有内容就留着，用户可能只是切了个 App。
            if !focused, !isSubmitting, text.trimmingCharacters(in: .whitespaces).isEmpty {
                isEditing = false
            }
        }
    }
}
```

- [ ] **Step 3: 语法检查**

```bash
make ios-parse
```

- [ ] **Step 4: 提交**

```bash
git add apps/ios/AimApp/Features/Home/TaskQuickAddRow.swift apps/ios/AimApp.xcodeproj/project.pbxproj
git commit -m "feat(ios): 今天组底部的快速添加待办行"
```

---

### Task 6: 完整表单 `TaskComposerView`

**Files:**
- Create: `apps/ios/AimApp/Features/Home/TaskComposerView.swift`
- Create: `apps/ios/AimApp/Tests/TaskComposerViewTests.swift`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces:
  - `struct TaskDraft { let title: String; let detail: String?; let dueAt: Date?; let assignedMemberID: UUID? }`
  - `TaskComposerView(members: [FamilyMember], save: @escaping (TaskDraft) async -> String?)` — `save` 返回 nil 表示成功，否则是要显示的错误文案
  - `static func defaultDueDate(now: Date, calendar: Calendar = PregnancyDateCalculator.calendar) -> Date`

- [ ] **Step 1: 登记 pbxproj**

为 `Features/Home/TaskComposerView.swift`（`A1…0134` / `A2…0134`，Home 分组，App Sources）和 `Tests/TaskComposerViewTests.swift`（`A1…0137` / `A2…0137`，Tests 分组，`A30000000000000000000006` Sources）各加四处条目。

- [ ] **Step 2: 写失败的测试**

`apps/ios/AimApp/Tests/TaskComposerViewTests.swift`：

```swift
import XCTest
@testable import AimApp

final class TaskComposerViewTests: XCTestCase {
    private let calendar = PregnancyDateCalculator.calendar

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func testDefaultDueIsTodayAtEightPmBeforeEightPm() {
        XCTAssertEqual(TaskComposerView.defaultDueDate(now: at(14, 10, 30)), at(14, 20))
        XCTAssertEqual(TaskComposerView.defaultDueDate(now: at(14, 19, 59)), at(14, 20))
    }

    func testDefaultDueRollsToTomorrowFromEightPm() {
        XCTAssertEqual(TaskComposerView.defaultDueDate(now: at(14, 20, 0)), at(15, 20))
        XCTAssertEqual(TaskComposerView.defaultDueDate(now: at(14, 23, 30)), at(15, 20))
    }
}
```

- [ ] **Step 3: 跑测试确认编译失败**

```bash
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests/TaskComposerViewTests test 2>&1 | grep -E "error:|TEST" | head
```

预期：`cannot find 'TaskComposerView' in scope`。

- [ ] **Step 4: 实现**

```swift
import SwiftUI

struct TaskDraft: Equatable {
    let title: String
    let detail: String?
    let dueAt: Date?
    let assignedMemberID: UUID?
}

/// `+` 菜单里的「新建待办」。快速添加只填标题；要定时间、要指派给谁，来这里。
struct TaskComposerView: View {
    @Environment(\.dismiss) private var dismiss
    let members: [FamilyMember]
    /// 返回 nil 表示成功；否则是要在表单里显示的错误文案。
    let save: (TaskDraft) async -> String?

    @State private var title = ""
    @State private var detail = ""
    @State private var hasDueDate = true
    @State private var dueAt: Date
    @State private var assignedMemberID: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(members: [FamilyMember], now: Date = .now, save: @escaping (TaskDraft) async -> String?) {
        self.members = members
        self.save = save
        _dueAt = State(initialValue: Self.defaultDueDate(now: now))
    }

    /// 默认今天 20:00；已经过了 20:00 就明天 20:00——给的是一个还来得及做的时刻。
    static func defaultDueDate(now: Date, calendar: Calendar = PregnancyDateCalculator.calendar) -> Date {
        let todayEight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: calendar.startOfDay(for: now)) ?? now
        if now < todayEight { return todayEight }
        return calendar.date(byAdding: .day, value: 1, to: todayEight) ?? todayEight
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("要做什么", text: $title)
                        .accessibilityIdentifier("task-composer-title")
                    TextField("补充说明（可选）", text: $detail, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("安排") {
                    Toggle("设置截止时间", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("截止", selection: $dueAt, displayedComponents: [.date, .hourAndMinute])
                    }
                    Picker("负责人", selection: $assignedMemberID) {
                        Text("未指派").tag(UUID?.none)
                        ForEach(members) { member in
                            Text(member.displayName).tag(UUID?.some(member.accountID))
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.aimDanger) }
                }
            }
            .navigationTitle("新建待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("保存") { Task { await submit() } }
                            .disabled(trimmedTitle.isEmpty)
                            .accessibilityIdentifier("task-composer-save")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = TaskDraft(
            title: trimmedTitle,
            detail: trimmedDetail.isEmpty ? nil : trimmedDetail,
            dueAt: hasDueDate ? dueAt : nil,
            assignedMemberID: assignedMemberID)
        if let failure = await save(draft) {
            errorMessage = failure
        } else {
            dismiss()
        }
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

同 Step 3 命令。预期 `Executed 2 tests, with 0 failures`。

- [ ] **Step 6: 提交**

```bash
git add apps/ios/AimApp/Features/Home/TaskComposerView.swift apps/ios/AimApp/Tests/TaskComposerViewTests.swift apps/ios/AimApp.xcodeproj/project.pbxproj
git commit -m "feat(ios): 新建待办的完整表单"
```

---

### Task 7: 首页头部 `HomeHeader`

**Files:**
- Move: `apps/ios/AimApp/Features/Timeline/TimelineHeader.swift` → `apps/ios/AimApp/Features/Home/HomeHeader.swift`（整体重写）
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `HomeHeader(week: Int?, days: Int, date: Date, stageName: String?, onOpenTimeline: () -> Void, onNewTask: () -> Void, onNewRecord: () -> Void, onAgent: () -> Void)`
- `TimelineHeader` 类型消失；`TimelineView` 对它的引用在 Task 9 移除。本任务结束时 `make ios-parse` 仍通过（parse 不做类型检查），但整体编译要到 Task 9 才恢复。

- [ ] **Step 1: 移动文件并改 pbxproj**

```bash
git mv apps/ios/AimApp/Features/Timeline/TimelineHeader.swift apps/ios/AimApp/Features/Home/HomeHeader.swift
```

pbxproj 里四处把 `Features/Timeline/TimelineHeader.swift` 全部替换为 `Features/Home/HomeHeader.swift`（编号 `A1…0057` / `A2…0058` 不变），并把 `A10000000000000000000057 /* Features/Home/HomeHeader.swift */,` 这一行从 `A40000000000000000000103 /* Timeline */` 的 children 挪到 `A40000000000000000000106 /* Home */` 的 children。

- [ ] **Step 2: 重写内容**

`HomeHeader.swift` 全文：

```swift
import SwiftUI

/// 首页头部。大标题是孕周而不是日期——时间线的主语是孕期进程。
/// 整块标题可点，是进入完整时间线的主入口；右侧只留「+」和 Agent 两颗钮，
/// 筛选跟着时间线走了。
struct HomeHeader: View {
    let week: Int?
    let days: Int
    let date: Date
    let stageName: String?
    let onOpenTimeline: () -> Void
    let onNewTask: () -> Void
    let onNewRecord: () -> Void
    let onAgent: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            Button(action: onOpenTimeline) {
                VStack(alignment: .leading, spacing: AimMetrics.space4) {
                    Text(captionText)
                        .font(.caption2)
                        .tracking(0.9)
                        .foregroundStyle(Color.aimAccent)
                    HStack(alignment: .firstTextBaseline, spacing: AimMetrics.space4) {
                        Text(titleText)
                            .font(.largeTitle.weight(.medium))
                            .foregroundStyle(Color.aimTextPrimary)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.aimTextTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(titleText)，查看完整时间线")
            .accessibilityIdentifier("home-header-week")

            Spacer(minLength: AimMetrics.space8)

            HStack(spacing: AimMetrics.space8) {
                Menu {
                    Button("新建待办", systemImage: "checkmark.circle", action: onNewTask)
                    Button("新增记录", systemImage: "square.and.pencil", action: onNewRecord)
                } label: {
                    circle("plus", tinted: false)
                }
                .accessibilityLabel("新增")
                .accessibilityIdentifier("home-add-menu")

                Button(action: onAgent) { circle("wand.and.sparkles", tinted: true) }
                    .accessibilityLabel("AIM")
                    .accessibilityIdentifier("global-agent-button")
            }
        }
        .padding(.horizontal, AimMetrics.space20)
        .padding(.bottom, AimMetrics.space12)
    }

    private func circle(_ symbol: String, tinted: Bool) -> some View {
        Image(systemName: symbol)
            .font(.subheadline)
            .foregroundStyle(tinted ? Color.aimAccent : Color.aimTextSecondary)
            .frame(width: AimMetrics.circleButtonSize, height: AimMetrics.circleButtonSize)
            .background(tinted ? Color.aimAccentSoft : Color.aimSurface, in: Circle())
            .overlay {
                if !tinted { Circle().stroke(Color.aimSeparator, lineWidth: 1) }
            }
    }

    private var titleText: String {
        guard let week else { return "孕期" }
        return days > 0 ? "孕 \(week) 周 + \(days) 天" : "孕 \(week) 周"
    }

    private var captionText: String {
        let formatter = DateFormatter()
        formatter.calendar = PregnancyDateCalculator.calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        let dateText = formatter.string(from: date)
        guard let stageName else { return dateText }
        return dateText + " · " + stageName
    }
}
```

- [ ] **Step 3: 语法检查**

```bash
make ios-parse
```

- [ ] **Step 4: 提交**

```bash
git add -A apps/ios/AimApp/Features/Home apps/ios/AimApp/Features/Timeline apps/ios/AimApp.xcodeproj/project.pbxproj
git commit -m "refactor(ios): 时间线头部改为首页头部，加入新增菜单与阶段"
```

---

### Task 8: 首页 `HomeView` 并接入 Tab

**Files:**
- Create: `apps/ios/AimApp/Features/Home/HomeView.swift`
- Modify: `apps/ios/AimApp/App/AimApp.swift:47`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TimelineStore` 派生属性（Task 3）、`AimTaskRow`（Task 4）、`TaskQuickAddRow`（Task 5）、`TaskComposerView` / `TaskDraft`（Task 6）、`HomeHeader`（Task 7）、现有 `AimFocusCard`、`AimRecordRow`、`TaskDetailView`、`TaskDelaySheet`、`RecordComposerView`、`RecordDetailView`、`AgentView`、`AimToastMessage`、`AimErrorState`
- Consumes（Task 9 才会有）: `TimelineView(store:planStore:recordStore:agentStore:)` 作为 push 目标。本任务先按该签名调用；Task 9 前整体编译不通过是预期的。
- Produces: `HomeView(store: TimelineStore, planStore: PlanStore, recordStore: RecordStore, agentStore: AgentStore)`

- [ ] **Step 1: 登记 pbxproj**

为 `Features/Home/HomeView.swift`（`A1…0132` / `A2…0132`，Home 分组，App Sources）加四处条目。

- [ ] **Step 2: 写 `HomeView`**

```swift
import SwiftUI

/// 「孕期」Tab 的根：以今天为顶的总控页。
///
/// 之前首页就是整条时间线，今天夹在过去与未来中间，靠启动时 scrollTo 定位——
/// List 懒加载让这一跳经常静默失败，过去内容越多今天就越沉底。现在今天天然在顶部，
/// 完整时间线从标题 push 进去，过去的周在那边折叠。
struct HomeView: View {
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: TimelineStore
    let planStore: PlanStore
    let recordStore: RecordStore
    let agentStore: AgentStore

    @State private var showingTimeline = false
    @State private var showingTaskComposer = false
    @State private var showingRecordComposer = false
    @State private var showingAgent = false
    @State private var toast: AimToastMessage?
    @State private var delayTarget: TaskItem?
    @State private var recordPromptTask: TaskItem?
    @State private var focusDetailTask: TaskItem?
    @State private var pendingTaskID: UUID?
    @State private var completedTaskID: UUID?

    @State private var isQuickAdding = false
    @State private var quickAddText = ""
    @State private var isQuickAddSubmitting = false
    @State private var quickAddError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HomeHeader(
                    week: store.currentWeek,
                    days: store.currentDays,
                    date: store.today,
                    stageName: store.stageName,
                    onOpenTimeline: { showingTimeline = true },
                    onNewTask: { showingTaskComposer = true },
                    onNewRecord: { if session.pregnancyID != nil { showingRecordComposer = true } },
                    onAgent: {
                        agentStore.focus(context: agentContext)
                        showingAgent = true
                    }
                )
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.aimCanvas)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: session.pregnancyID) {
                guard session.pregnancyID != nil, store.weeks.isEmpty else { return }
                await store.load()
            }
            .navigationDestination(isPresented: $showingTimeline) {
                TimelineView(store: store, planStore: planStore, recordStore: recordStore, agentStore: agentStore)
            }
            .navigationDestination(item: $focusDetailTask) { task in
                TaskDetailView(task: task, repository: planStore.repository)
            }
            .sheet(isPresented: $showingTaskComposer) {
                TaskComposerView(members: store.familyMembers, now: store.now) { draft in
                    let ok = await store.createTask(
                        title: draft.title, description: draft.detail,
                        dueAt: draft.dueAt, assignedMemberID: draft.assignedMemberID)
                    return ok ? nil : (store.errorMessage ?? "没能保存这条待办，稍后再试。")
                }
            }
            .sheet(isPresented: $showingRecordComposer) {
                RecordComposerView(store: recordStore) {
                    showingRecordComposer = false
                    Task { await store.load() }
                }
            }
            .sheet(item: $delayTarget) { task in
                TaskDelaySheet(task: task, repository: planStore.repository) { _ in
                    delayTarget = nil
                    Task { await store.load() }
                }
            }
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
            .fullScreenCover(isPresented: $showingAgent) {
                AgentView(store: agentStore) { showingAgent = false }
            }
            .aimToast($toast)
            .sensoryFeedback(.success, trigger: completedTaskID)
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if store.weeks.isEmpty, store.isLoading {
            ProgressView("正在整理今天")
        } else if store.weeks.isEmpty, let message = store.errorMessage {
            AimErrorState(message: message) { Task { await store.load() } }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if let focus = store.focusTask {
                AimFocusCard(task: focus) { focusDetailTask = focus }
                    .listRowInsets(EdgeInsets(top: AimMetrics.space8, leading: AimMetrics.space20,
                                              bottom: AimMetrics.space12, trailing: AimMetrics.space20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.aimCanvas)
                    .accessibilityIdentifier("home-focus-card")
            }

            Section {
                sectionHeader("今天 · \(store.todayTasks.count) 项", trailing: overdueBadge)
                if store.todayTasks.isEmpty {
                    quietRow("今天没有安排")
                }
                ForEach(store.todayTasks) { task in
                    taskRow(task, style: .due)
                }
                TaskQuickAddRow(
                    isEditing: $isQuickAdding,
                    text: $quickAddText,
                    isSubmitting: isQuickAddSubmitting,
                    errorMessage: quickAddError,
                    onSubmit: { Task { await submitQuickAdd() } }
                )
                .listRowInsets(rowInsets)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.aimCanvas)
            }

            if !store.upcomingTasks.isEmpty {
                Section {
                    sectionHeader("接下来 7 天")
                    ForEach(store.upcomingTasks.prefix(5)) { task in
                        taskRow(task, style: .upcoming)
                    }
                    if store.upcomingTasks.count > 5 {
                        linkRow("还有 \(store.upcomingTasks.count - 5) 项 · 查看时间线")
                    }
                }
            }

            Section {
                sectionHeader("最近记录", trailing: AnyView(
                    Button("全部") { showingTimeline = true }
                        .font(.caption2)
                        .foregroundStyle(Color.aimAccent)
                        .buttonStyle(.plain)
                ))
                if store.recentRecords.isEmpty {
                    quietRow("还没有记录")
                }
                ForEach(store.recentRecords) { record in
                    NavigationLink {
                        RecordDetailView(record: record, store: recordStore, planStore: planStore, agentStore: agentStore)
                    } label: {
                        AimRecordRow(record: record)
                    }
                    .listRowInsets(rowInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.aimCanvas)
                    .accessibilityIdentifier("record-row-\(record.type.rawValue)")
                }
            }

            Section {
                linkRow("查看完整时间线")
                    .accessibilityIdentifier("home-open-timeline")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.aimCanvas)
        .refreshable { await store.load() }
        .safeAreaPadding(.bottom, AimMetrics.space28)
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: AimMetrics.space20, bottom: 0, trailing: AimMetrics.space20)
    }

    private var overdueBadge: AnyView? {
        guard store.overdueCount > 0 else { return nil }
        return AnyView(
            Text("逾期 \(store.overdueCount)")
                .font(.caption2)
                .foregroundStyle(Color.aimDanger)
        )
    }

    private func sectionHeader(_ title: String, trailing: AnyView? = nil) -> some View {
        HStack {
            Text(title).aimLabelStyle()
            Spacer()
            if let trailing { trailing }
        }
        .padding(.top, AimMetrics.space16)
        .padding(.bottom, AimMetrics.space4)
        .listRowInsets(rowInsets)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.aimCanvas)
        .accessibilityAddTraits(.isHeader)
    }

    private func quietRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.aimTextTertiary)
            .padding(.vertical, AimMetrics.space8)
            .listRowInsets(rowInsets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.aimCanvas)
    }

    private func linkRow(_ text: String) -> some View {
        Button { showingTimeline = true } label: {
            HStack(spacing: AimMetrics.space4) {
                Text(text).font(.subheadline.weight(.medium))
                Image(systemName: "arrow.right").font(.footnote)
            }
            .foregroundStyle(Color.aimAccent)
            .padding(.vertical, AimMetrics.space8)
        }
        .buttonStyle(.plain)
        .listRowInsets(rowInsets)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.aimCanvas)
    }

    private func taskRow(_ task: TaskItem, style: AimTaskRow.Style) -> some View {
        NavigationLink {
            TaskDetailView(task: task, repository: planStore.repository)
        } label: {
            AimTaskRow(
                task: task,
                assigneeName: store.assigneeName(for: task.assignedMemberID),
                now: store.now,
                isOverdue: store.isOverdue(task),
                isPending: pendingTaskID == task.id,
                style: style
            ) {
                Task { await complete(task) }
            }
        }
        .listRowInsets(rowInsets)
        .listRowSeparator(.visible)
        .listRowSeparatorTint(Color.aimSeparator)
        .listRowBackground(Color.aimCanvas)
        .accessibilityIdentifier("home-task-row")
        .swipeActions(edge: .leading) {
            Button {
                Task { await complete(task) }
            } label: {
                Label("完成", systemImage: "checkmark")
            }
            .tint(Color.aimSuccess)
        }
        .swipeActions(edge: .trailing) {
            Button {
                delayTarget = task
            } label: {
                Label("延期", systemImage: "calendar")
            }
            .tint(Color.aimAccent)
        }
    }

    // MARK: - 动作

    private func complete(_ task: TaskItem) async {
        guard pendingTaskID == nil else { return }
        pendingTaskID = task.id
        defer { pendingTaskID = nil }
        if await store.complete(task) {
            completedTaskID = task.id
            toast = AimToastMessage(
                text: "已完成「\(task.title)」",
                undoTitle: "记一下",
                accessibilityIdentifier: "complete-task-record-prompt"
            ) {
                recordPromptTask = task
            }
        } else {
            toast = AimToastMessage(text: store.errorMessage ?? "没能标记完成，稍后再试。", undoTitle: "", accessibilityIdentifier: "home-complete-failed")
        }
    }

    private func submitQuickAdd() async {
        let title = quickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            isQuickAdding = false
            return
        }
        isQuickAddSubmitting = true
        quickAddError = nil
        defer { isQuickAddSubmitting = false }
        if await store.createTask(title: title, dueAt: TaskDateText.endOfDay(store.now)) {
            quickAddText = ""
        } else {
            quickAddError = store.errorMessage ?? "没能保存这条待办，稍后再试。"
        }
    }

    private var agentContext: AgentContext {
        let week = store.currentWeek.map { "孕 \($0) 周" } ?? "孕期"
        var lines = [week]
        if let focus = store.focusTask { lines.append("当前最重要：" + focus.title) }
        if !store.todayTasks.isEmpty { lines.append("今天还有 \(store.todayTasks.count) 项待办") }
        return AgentContext(title: "今天", summary: lines.joined(separator: "\n"))
    }
}
```

失败 toast 不传 `undo` 闭包，`AimToastModifier` 只在 `message.undo != nil` 时渲染撤销按钮，所以 `undoTitle: ""` 不会出现空按钮。

- [ ] **Step 3: 接入 Tab**

`App/AimApp.swift` 第 47 行 `TimelineView(store: timelineStore, planStore: planStore, recordStore: recordStore, agentStore: agentStore)` 改为 `HomeView(store: timelineStore, planStore: planStore, recordStore: recordStore, agentStore: agentStore)`。

- [ ] **Step 4: 语法检查**

```bash
make ios-parse
```

- [ ] **Step 5: 提交**

```bash
git add apps/ios/AimApp/Features/Home/HomeView.swift apps/ios/AimApp/App/AimApp.swift apps/ios/AimApp.xcodeproj/project.pbxproj
git commit -m "feat(ios): 以今天为顶的首页"
```

---

### Task 9: `TimelineView` 改为次级页

**Files:**
- Modify: `apps/ios/AimApp/Features/Timeline/TimelineView.swift`（整体重写）

**Interfaces:**
- Consumes: `TimelineStore.pastWeeks`、`isPastExpanded`（Task 3）
- Produces: `TimelineView(store:planStore:recordStore:agentStore:)`，无 `NavigationStack`，供 `HomeView` push

- [ ] **Step 1: 重写 `TimelineView.swift`**

```swift
import SwiftUI

/// 完整的孕期时间线，从首页标题 push 进来。
///
/// 过去的周折叠在顶部一行里，今天所在周因此天然是第一个分组——不再需要启动时
/// `scrollTo`，那一跳在 List 懒加载下并不可靠。「回到今天」只在展开过去周后出现，
/// 点击即收起，今天就回到顶部；随后的 `scrollTo` 失败也无碍。
struct TimelineView: View {
    @Bindable var store: TimelineStore
    let planStore: PlanStore
    let recordStore: RecordStore
    let agentStore: AgentStore

    @State private var toast: AimToastMessage?
    @State private var delayTarget: TaskItem?
    @State private var completedTaskID: UUID?
    @State private var recordPromptTask: TaskItem?

    private let todayAnchor = "timeline-today"

    var body: some View {
        Group {
            if store.weeks.isEmpty, store.isLoading {
                ProgressView("正在整理孕期时间线")
            } else if store.weeks.isEmpty, let message = store.errorMessage {
                AimErrorState(message: message) { Task { await store.load() } }
            } else {
                timeline
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.aimCanvas)
        .navigationTitle("孕期时间线")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("筛选", selection: $store.filter) {
                        ForEach(TimelineFilter.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(store.filter == .all ? Color.aimTextSecondary : Color.aimAccent)
                }
                .accessibilityLabel("筛选")
                .accessibilityIdentifier("timeline-filter")
            }
        }
        .refreshable { await store.load() }
        .sheet(item: $delayTarget) { task in
            TaskDelaySheet(task: task, repository: planStore.repository) { _ in
                delayTarget = nil
                Task { await store.load() }
            }
        }
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
        .aimToast($toast)
        .sensoryFeedback(.success, trigger: completedTaskID)
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            List {
                if !store.pastWeeks.isEmpty {
                    Section {
                        pastToggleRow
                    }
                    if store.isPastExpanded {
                        ForEach(store.pastWeeks) { week in
                            Section {
                                rows(for: week)
                            } header: {
                                header(for: week)
                            }
                        }
                    }
                }
                ForEach(store.weeks.filter { $0.position != .past }) { week in
                    Section {
                        rows(for: week)
                    } header: {
                        header(for: week)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.aimCanvas)
            .overlay(alignment: .bottom) {
                if store.isPastExpanded { backToToday(proxy) }
            }
        }
    }

    private var pastToggleRow: some View {
        Button {
            withAnimation(.snappy) { store.isPastExpanded.toggle() }
        } label: {
            HStack {
                Text(pastSummary)
                    .font(.footnote)
                    .foregroundStyle(Color.aimTextSecondary)
                Spacer()
                Image(systemName: store.isPastExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.aimTextTertiary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, AimMetrics.space8)
        .listRowInsets(EdgeInsets(top: 0, leading: AimMetrics.rowLeadingInset,
                                  bottom: 0, trailing: AimMetrics.space16))
        .listRowSeparator(.hidden)
        .listRowBackground(AimTimelineRail(position: .past))
        .accessibilityIdentifier("timeline-past-collapsed")
    }

    private var pastSummary: String {
        let past = store.pastWeeks
        guard let first = past.first?.week, let last = past.last?.week else { return "之前" }
        let count = past.reduce(0) { $0 + $1.entries.count }
        let range = first == last ? "孕 \(first) 周" : "孕 \(first)–\(last) 周"
        return "之前 · \(range) · \(count) 项"
    }

    private func header(for week: TimelineWeek) -> some View {
        let isCurrent = week.position == .current
        return AimWeekHeader(week: week.week, startDate: week.startDate, endDate: week.endDate,
                              position: week.position, count: week.entries.count)
            .listRowInsets(EdgeInsets(top: 0, leading: AimMetrics.rowLeadingInset,
                                      bottom: 0, trailing: AimMetrics.space16))
            .listRowBackground(AimTimelineRail(position: week.position, showsDot: true))
            .id(isCurrent ? todayAnchor : "week-\(week.week)")
    }

    @ViewBuilder
    private func rows(for week: TimelineWeek) -> some View {
        if store.isCollapsed(week) {
            Button { store.expand(week) } label: {
                HStack {
                    Text("孕 \(week.week) 周 · \(week.entries.count) 项")
                        .font(.footnote)
                        .foregroundStyle(Color.aimTextTertiary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.aimTextTertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, AimMetrics.space8)
            .listRowInsets(EdgeInsets(top: 0, leading: AimMetrics.rowLeadingInset,
                                      bottom: 0, trailing: AimMetrics.space16))
            .listRowSeparator(.hidden)
            .listRowBackground(AimTimelineRail(position: week.position))
            .accessibilityIdentifier("timeline-week-collapsed-\(week.week)")
        } else {
            ForEach(week.entries) { entry in
                row(entry)
                    .listRowInsets(EdgeInsets(top: 0, leading: AimMetrics.rowLeadingInset,
                                              bottom: 0, trailing: AimMetrics.space16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(AimTimelineRail(position: week.position))
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: TimelineEntry) -> some View {
        switch entry {
        case let .task(task):
            NavigationLink {
                TaskDetailView(task: task, repository: planStore.repository)
            } label: {
                AimTaskRow(
                    task: task,
                    assigneeName: store.assigneeName(for: task.assignedMemberID),
                    now: store.now,
                    isOverdue: task.isOpen && store.isOverdue(task)
                )
            }
            .accessibilityIdentifier("timeline-task-row")
            .swipeActions(edge: .leading) {
                if task.isOpen {
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
                }
            }
            .swipeActions(edge: .trailing) {
                if task.isOpen {
                    Button {
                        delayTarget = task
                    } label: {
                        Label("延期", systemImage: "calendar")
                    }
                    .tint(Color.aimAccent)
                }
            }
        case let .record(record):
            NavigationLink {
                RecordDetailView(record: record, store: recordStore, planStore: planStore, agentStore: agentStore)
            } label: {
                AimRecordRow(record: record)
            }
            .accessibilityIdentifier("record-row-\(record.type.rawValue)")
        }
    }

    private func backToToday(_ proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.snappy) { store.isPastExpanded = false }
            proxy.scrollTo(todayAnchor, anchor: .top)
        } label: {
            Label("回到今天", systemImage: "arrow.up.to.line")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, AimMetrics.space16)
                .padding(.vertical, AimMetrics.space8)
                .background(Color.aimSurfaceRaised, in: Capsule())
                .overlay { Capsule().stroke(Color.aimSeparator, lineWidth: 1) }
                .foregroundStyle(Color.aimAccent)
        }
        .padding(.bottom, AimMetrics.space12)
        .accessibilityIdentifier("timeline-back-to-today")
    }
}
```

时间线的今天分组不再放焦点卡、不再排除焦点任务；`TodayOffsetKey`、`showsBackToToday`、`showingComposer`、`showingAgent`、`focusDetailTask` 全部删除。

- [ ] **Step 2: 整体编译**

```bash
make ios-parse && make ios-build 2>&1 | grep -E "error:|BUILD" | tail
```

预期 `** BUILD SUCCEEDED **`。常见报错与处理：

- `AimTaskRow` 的 `Style` 不可见：确认 Task 4 已提交。
- `TaskComposerView(members:now:save:)` 找不到：确认 Task 6 的 `init` 含 `now:` 参数。
- `store.filter` 绑定报错：`@Bindable var store` 已在结构体顶部声明。

- [ ] **Step 3: 跑全部单元测试**

```bash
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests test 2>&1 | grep -E "error:|Executed|TEST" | tail
```

预期 `** TEST SUCCEEDED **`。

- [ ] **Step 4: 提交**

```bash
git add apps/ios/AimApp/Features/Timeline/TimelineView.swift
git commit -m "feat(ios): 时间线降为次级页，过去周折叠在顶部"
```

---

### Task 10: 清理遗留：删除 `TodayStore`，归位 `PregnancySetupView`

**Files:**
- Delete: `apps/ios/AimApp/Features/Today/TodayStore.swift`
- Delete: `apps/ios/AimApp/Tests/TodayStoreTests.swift`
- Move: `apps/ios/AimApp/Features/Today/TodayView.swift` → `apps/ios/AimApp/Features/Onboarding/PregnancySetupView.swift`，并删除其中无调用点的 `struct TaskRow`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

- [ ] **Step 1: 确认无引用**

```bash
grep -rn "TodayStore\|TaskRow(" apps/ios/AimApp --include='*.swift' | grep -v "AimTaskRow\|Features/Today/\|Tests/TodayStoreTests"
```

预期无输出。若有输出，先处理引用再继续。

- [ ] **Step 2: 移动与删除**

```bash
git rm apps/ios/AimApp/Features/Today/TodayStore.swift apps/ios/AimApp/Tests/TodayStoreTests.swift
git mv apps/ios/AimApp/Features/Today/TodayView.swift apps/ios/AimApp/Features/Onboarding/PregnancySetupView.swift
```

打开 `PregnancySetupView.swift`，删掉文件末尾从 `struct TaskRow: View {` 到文件结束的整段（约第 158–180 行）。`PregnancySetupView`、`PregnancyDateMode`、`PregnancyDateCalculator` 保留。

- [ ] **Step 3: 改 pbxproj**

- 删除含 `Features/Today/TodayStore.swift` 的三行（`PBXBuildFile` 的 `A2…0021`、`PBXFileReference` 的 `A1…0021`、`A30000000000000000000004` files 里的 `A2…0021`）。
- 删除含 `Tests/TodayStoreTests.swift` 的三行（`A2…0032`、`A1…0032`、`A30000000000000000000006` files 里的 `A2…0032`）与 `A40000000000000000000014 /* Tests */` children 里的那一行。
- 把 `Features/Today/TodayView.swift` 四处全部替换为 `Features/Onboarding/PregnancySetupView.swift`（编号 `A1…0022` / `A2…0022` 不变）。
- 把 `A10000000000000000000022 /* Features/Onboarding/PregnancySetupView.swift */,` 从 `A40000000000000000000011 /* Today */` 的 children 挪到 `A40000000000000000000008 /* Onboarding */` 的 children。
- 删除整个 `A40000000000000000000011 /* Today */ = { … };` 分组定义，以及引用它的 `A40000000000000000000011 /* Today */,` 那一行（约第 294 行）。

```bash
grep -n "Today" apps/ios/AimApp.xcodeproj/project.pbxproj
```

预期无输出。

- [ ] **Step 4: 编译 + 单元测试**

```bash
make ios-parse && make ios-build 2>&1 | grep -E "error:|BUILD" | tail
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppTests test 2>&1 | grep -E "error:|Executed|TEST" | tail
```

- [ ] **Step 5: 提交**

```bash
git add -A apps/ios/AimApp apps/ios/AimApp.xcodeproj/project.pbxproj
git commit -m "refactor(ios): 删除无引用的 TodayStore，孕期录入页归位到 Onboarding"
```

---

### Task 11: UI 测试更新与新增

**Files:**
- Modify: `apps/ios/AimApp/UITests/CoreJourneyUITests.swift`

前置：另一个终端在仓库根目录运行 `make dev`，等 `http://127.0.0.1:8100/api/v1/health` 返回 200。

- [ ] **Step 1: 改现有用例**

1. `testRecordsJourneyCreatesSymptomAndOffersTaskAction`（约第 41 行）与另一处 `app.buttons["新增记录"]`（约第 404 行）：`新增记录` 现在在 `+` 菜单里。把

```swift
        let addRecord = app.buttons["新增记录"]
        XCTAssertTrue(addRecord.waitForExistence(timeout: 5))
        addRecord.tap()
```

改为

```swift
        let addMenu = app.buttons["home-add-menu"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 5))
        addMenu.tap()
        let addRecord = app.buttons["新增记录"]
        XCTAssertTrue(addRecord.waitForExistence(timeout: 3))
        addRecord.tap()
```

2. 约第 78–82 行与第 150–154 行的 `anyWeekHeader`（`identifier BEGINSWITH 'timeline-week-header-'`）：首页不再有周分组头。改为等待 `home-focus-card`：

```swift
        let focusCard = app.descendants(matching: .any).matching(identifier: "home-focus-card").firstMatch
        XCTAssertTrue(focusCard.waitForExistence(timeout: 15))
```

3. `testCompletingATaskOffersToRecordTheResult`（约第 109–116 行）：改为点 checkbox。把

```swift
        let taskRow = app.buttons.matching(identifier: "timeline-task-row").firstMatch
        XCTAssertTrue(taskRow.waitForExistence(timeout: 8))
        taskRow.swipeRight()

        let completeAction = app.buttons["完成"]
        XCTAssertTrue(completeAction.waitForExistence(timeout: 3))
        completeAction.tap()
```

改为

```swift
        // 行合并成了单个无障碍元素，checkbox 不单独暴露；对行做左滑露出「完成」
        // 与点 checkbox 等价，而且不依赖行内按钮的命中区域。
        let taskRow = app.buttons.matching(identifier: "home-task-row").firstMatch
        XCTAssertTrue(taskRow.waitForExistence(timeout: 8))
        taskRow.swipeRight()

        let completeAction = app.buttons["完成"]
        XCTAssertTrue(completeAction.waitForExistence(timeout: 3))
        completeAction.tap()
```

若新账号的种子任务全在焦点卡里、今天组没有其它行，`home-task-row` 会找不到：改为先 `app.buttons["home-quick-add"].tap()`，往 `home-quick-add-field` 里输入「测试待办\n」，再等 `home-task-row` 出现。

4. `testFocusCardActionOpensTaskDetailRatherThanAgent`：`reveal(action, in: app)` 保留；焦点卡现在在首屏，`reveal` 第一轮就命中。

- [ ] **Step 2: 新增快速添加用例**

```swift
    func testQuickAddCreatesATaskInTodayGroup() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        registerNewAccount(in: app)
        completePregnancySetup(in: app)

        XCTAssertTrue(app.tabBars.buttons["孕期"].waitForExistence(timeout: 15))

        let quickAdd = app.buttons["home-quick-add"]
        reveal(quickAdd, in: app)
        quickAdd.tap()

        let field = app.textFields["home-quick-add-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        let title = "买叶酸 \(Int.random(in: 100...999))"
        field.typeText(title + "\n")

        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), "新待办应出现在今天组")
        XCTAssertTrue(field.exists, "成功后输入框应保持打开，方便连续录入")
    }
```

- [ ] **Step 3: 新增时间线导航用例**

```swift
    func testHeaderOpensTimelineWithTodayOnTop() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        registerNewAccount(in: app)
        completePregnancySetup(in: app)

        let header = app.buttons["home-header-week"]
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        header.tap()

        XCTAssertTrue(app.navigationBars["孕期时间线"].waitForExistence(timeout: 5))
        let todayHeader = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'timeline-week-header-'"))
            .firstMatch
        XCTAssertTrue(todayHeader.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["timeline-filter"].exists)

        app.navigationBars["孕期时间线"].buttons.firstMatch.tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5), "返回后应回到首页")
    }
```

- [ ] **Step 4: 跑 UI 测试**

```bash
xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:AimAppUITests test 2>&1 | grep -E "error:|failed|Executed|TEST" | tail -20
```

预期 `** TEST SUCCEEDED **`。失败时看 `/tmp/aim-derived-data/Logs/Test/*.xcresult` 里的截图定位。

- [ ] **Step 5: 提交**

```bash
git add apps/ios/AimApp/UITests/CoreJourneyUITests.swift
git commit -m "test(ios): 首页快速添加与时间线导航的 UI 用例"
```

---

### Task 12: 模拟器人工验收（深色、大字号、逾期数据）

**Files:** 无代码改动，除非验收发现问题。

- [ ] **Step 1: 造一条逾期和一条下周的任务**

`make dev` 运行中，模拟器启动 App，用首页 `+` → 新建待办，分别建：截止「昨天 20:00」的「逾期测试」、截止「6 天后」的「下周测试」。刷新后核对：

- 焦点卡显示「逾期测试」；
- 今天组头右侧出现「逾期 1」当且仅当今天组里另有逾期行（只有一条逾期时它是焦点，头部不显示）；
- 「下周测试」在「接下来 7 天」组，checkbox 是虚线圆，日期显示「周X 20:00」。

- [ ] **Step 2: 时间线**

点标题进时间线：第一行是「之前 · …」（新账号无过去内容时不显示，改用一条 `occurredAt` 为上周的记录制造过去周），第二个分组是「今天」陶土色头。展开过去周 → 「回到今天」出现 → 点击后收起并回到顶部。

- [ ] **Step 3: 深色与 AX5**

模拟器 Settings → Developer → Dark Appearance 打开；Accessibility → Larger Text 拉到最大（AX5）。回到 App 检查首页与时间线：无白底白字，焦点卡与任务行文字不截断（`fixedSize(horizontal: false, vertical: true)` 已在 `AimFocusCard`），快速添加行在键盘弹出时不被遮挡。

- [ ] **Step 4: 记录问题并修复**

发现的问题按「症状 → 文件 → 修复」记录在提交信息里，修复后重跑 Task 9 Step 3 的单元测试。

```bash
git add -A apps/ios
git commit -m "fix(ios): 首页验收修正"
```

没有问题则跳过本步。

---

## 自检记录

- 规格 §4.1 头部 → Task 7；§4.2 焦点卡 → Task 3 + Task 8；§4.3 今天组与快速添加 → Task 3/4/5/8；§4.4 接下来 → Task 3/8；§4.5 最近记录 → Task 3/8；§4.6 底部链接 → Task 8；§4.7 容器与非吸顶分组头 → Task 8（分组头作为普通行）；§4.8 状态优先级 → Task 8 `content`；§5 时间线 → Task 9；§6.1 数据层 → Task 2/3；§6.2 → Task 5/8；§6.3 → Task 6；§7 → Task 1；§8 代码组织 → Task 7/8/10；§9 标识符 → Task 4/5/6/7/8/9；§10 测试 → Task 1/2/3/6/11；§11 不做项未出现在任何任务。
- 「失败但有数据 → 顶部错误条」（规格 §4.8）：现有 `TimelineView` 也未实现顶部错误条，本计划保持与现状一致（失败但有数据时静默保留数据，快速添加 / 完成失败各自有行内或 toast 反馈）。这是有意缩窄，实施时不必补。
