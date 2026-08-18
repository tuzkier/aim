# iOS 孕期时间线重设计 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 iOS 的「今天 / 计划 / 记录」三页合并为一条以孕周为刻度的连续时间线，建立完整的暖色设计 token 体系（含深色模式），并按三档执行权限补齐 Agent 的确认、告知与撤销机制。

**Architecture:** 时间线继续使用 `List`，导轨绘制在 `.listRowBackground` 中，以保留 `swipeActions`、`refreshable` 与 VoiceOver 遍历顺序。分组与排序逻辑抽为纯函数 `TimelineBuilder`，与视图完全解耦并单独测试。设计 token 以 colorset 形式进入 Assets 并带 Dark 外观，`AimTheme` 退化为类型安全的引用层。

**Tech Stack:** SwiftUI（iOS 17+）、Observation、SwiftData、XCTest、ExyteChat 3.2.8

**Spec:** `docs/superpowers/specs/2026-08-18-ios-timeline-redesign-design.md`

## Global Constraints

- 部署目标 iOS 17.0。不得使用 iOS 18+ API。
- **本工程的 `project.pbxproj` 使用显式文件引用，没有 `fileSystemSynchronizedGroups`。每新增一个 `.swift` 文件，必须手工添加三处条目**：`PBXFileReference`、`PBXBuildFile`、以及所属 `PBXGroup.children` 与对应 Sources 构建阶段的 `files` 列表。漏掉任何一处，文件不参与编译且不报错。
- 新 `PBXFileReference` ID 从 `A10000000000000000000041` 起递增；新 `PBXBuildFile` ID 从 `A20000000000000000000042` 起递增。已用最大值分别为 `...040` 与 `...041`。
- 主 target 的 Sources 构建阶段是 `A30000000000000000000001`；测试 target `AimAppTests` 的是 `A30000000000000000000002`。
- 相关 PBXGroup：`Core` = `A40000000000000000000003`、`Agent` = `A40000000000000000000006`、`Family` = `A40000000000000000000007`、`Records` = `A40000000000000000000102`、`Tests` = `A40000000000000000000014`、根 `AimApp` 组 = `A40000000000000000000001`。
- 全部颜色必须来自 Assets colorset，不得出现 `Color(red:green:blue:)`。
- 全部字体必须使用相对字体（`.body`、`.title3` 等），不得使用 `.system(size:)`。
- 文案一律简体中文，句子不加感叹号，不使用「请」。
- 每个任务结束时提交，commit message 使用 `feat(ios):` / `fix(ios):` / `refactor(ios):` 前缀。
- 编译验证：`make ios-build`。单元测试：`make ios-test`。单个测试类：
  `xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppTests/<类名>`

---

### Task 1: TaskItem 携带变更来源

时间线的 `Agent 调整` 标记依赖 `changed_by_actor_type`。该字段服务端已返回、`APITaskDTO` 已解码，但未映射进领域模型 `TaskItem`。

**Files:**
- Modify: `apps/ios/AimApp/Clients/BusinessAPIClient/BusinessRepository.swift:3-14`（`TaskItem`）与 `:246-248`（`map(_:)`）
- Test: `apps/ios/AimApp/Tests/BusinessRepositoryTests.swift`

**Interfaces:**
- Consumes: `APITaskDTO.changedByActorType: String`（已存在）
- Produces: `TaskItem.changedByActor: TaskActor`，`enum TaskActor { case account, agent, system, unknown }`，`TaskItem.isAgentChanged: Bool`

- [ ] **Step 1: 写失败测试**

在 `apps/ios/AimApp/Tests/BusinessRepositoryTests.swift` 末尾追加：

```swift
final class TaskActorMappingTests: XCTestCase {
    func testAgentActorRawValueMapsToAgent() {
        XCTAssertEqual(TaskActor(rawValue: "agent"), .agent)
        XCTAssertEqual(TaskActor(rawValue: "AGENT"), .agent)
    }

    func testAccountAndSystemActorsAreNotAgentChanged() {
        XCTAssertFalse(TaskActor.account.isAgent)
        XCTAssertFalse(TaskActor.system.isAgent)
        XCTAssertTrue(TaskActor.agent.isAgent)
    }

    func testUnrecognisedActorFallsBackToUnknown() {
        XCTAssertEqual(TaskActor(rawValue: "robot"), .unknown)
        XCTAssertFalse(TaskActor.unknown.isAgent)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppTests/TaskActorMappingTests`

Expected: 编译失败，`cannot find 'TaskActor' in scope`

- [ ] **Step 3: 实现**

在 `BusinessRepository.swift` 中 `TaskStatus` 定义之后插入：

```swift
enum TaskActor: String, Codable, Sendable {
    case account
    case agent
    case system
    case unknown

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "account": self = .account
        case "agent": self = .agent
        case "system": self = .system
        default: self = .unknown
        }
    }

    var isAgent: Bool { self == .agent }
}
```

把 `TaskItem` 改为：

```swift
struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let detail: String?
    let status: TaskStatus
    let version: Int
    let dueAt: Date?
    let scheduledFor: Date?
    let assignedMemberID: UUID?
    let changedByActor: TaskActor

    var isOpen: Bool { status != .completed }
    var isAgentChanged: Bool { changedByActor.isAgent }
}
```

把 `map(_ dto: APITaskDTO)` 改为：

```swift
    private func map(_ dto: APITaskDTO) -> TaskItem {
        TaskItem(
            id: dto.id,
            title: dto.title,
            detail: dto.description,
            status: TaskStatus(rawValue: dto.status),
            version: dto.version,
            dueAt: dto.dueAt,
            scheduledFor: dto.scheduledFor,
            assignedMemberID: dto.assignedMemberID,
            changedByActor: TaskActor(rawValue: dto.changedByActorType)
        )
    }
```

- [ ] **Step 4: 修复所有 TaskItem 构造点**

Run: `grep -rn "TaskItem(" apps/ios/AimApp --include="*.swift"`

对每一处构造（含 `TodayStore.preview()`、`PlanStore` 及各测试文件），补上 `changedByActor:` 参数。预览与测试数据统一使用 `.system`，除非该用例专门验证 Agent 标记。

- [ ] **Step 5: 运行测试确认通过**

Run: `make ios-test`
Expected: PASS，无编译错误

- [ ] **Step 6: 提交**

```bash
git add apps/ios/AimApp
git commit -m "feat(ios): carry task change actor into domain model"
```

---

### Task 2: 时间线分组逻辑

把任务与记录合并成按孕周分组的时间线。纯函数，无 UI 依赖，是整个时间线的地基。

**Files:**
- Create: `apps/ios/AimApp/Features/Timeline/TimelineModels.swift`
- Create: `apps/ios/AimApp/Features/Timeline/TimelineBuilder.swift`
- Create: `apps/ios/AimApp/Tests/TimelineBuilderTests.swift`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TaskItem`（Task 1）、`RecordItem`（`Features/Records/RecordModels.swift`）
- Produces:
  - `enum TimelineEntry { case task(TaskItem), record(RecordItem) }`，含 `var id: String`、`var date: Date`
  - `struct TimelineWeek { let week: Int; let startDate: Date; let endDate: Date; let position: TimelineWeek.Position; let entries: [TimelineEntry] }`
  - `enum TimelineBuilder`，静态方法 `lastMenstrualPeriod(asOf:weeks:days:)`、`week(for:lastMenstrualPeriod:)`、`build(tasks:records:lastMenstrualPeriod:today:)`

- [ ] **Step 1: 写失败测试**

创建 `apps/ios/AimApp/Tests/TimelineBuilderTests.swift`：

```swift
import XCTest
@testable import AimApp

final class TimelineBuilderTests: XCTestCase {
    private let calendar = PregnancyDateCalculator.calendar

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }

    private func task(_ title: String, due: Date?, actor: TaskActor = .system) -> TaskItem {
        TaskItem(id: UUID(), title: title, detail: nil, status: .todo, version: 1,
                 dueAt: due, scheduledFor: nil, assignedMemberID: nil, changedByActor: actor)
    }

    private func record(_ occurred: Date) -> RecordItem {
        RecordItem(
            id: UUID(),
            pregnancyID: UUID(),
            familyID: UUID(),
            authorAccountID: UUID(),
            type: .note,
            occurredAt: occurred,
            visibility: .family,
            title: "记录",
            content: "内容",
            structuredData: .note,
            attachmentRefs: [],
            createdAt: occurred,
            updatedAt: occurred
        )
    }

    func testDerivesLastMenstrualPeriodFromGestationalAge() {
        let asOf = date(2026, 8, 14)
        let lmp = TimelineBuilder.lastMenstrualPeriod(asOf: asOf, weeks: 18, days: 3)
        XCTAssertEqual(calendar.startOfDay(for: lmp), calendar.startOfDay(for: date(2026, 4, 7)))
    }

    func testWeekBoundariesAreSevenDaysWide() {
        let lmp = date(2026, 4, 7)
        XCTAssertEqual(TimelineBuilder.week(for: date(2026, 8, 11), lastMenstrualPeriod: lmp), 18)
        XCTAssertEqual(TimelineBuilder.week(for: date(2026, 8, 17), lastMenstrualPeriod: lmp), 18)
        XCTAssertEqual(TimelineBuilder.week(for: date(2026, 8, 18), lastMenstrualPeriod: lmp), 19)
    }

    func testMergesTasksAndRecordsIntoSameWeekSortedByDate() {
        let lmp = date(2026, 4, 7)
        let weeks = TimelineBuilder.build(
            tasks: [task("散步", due: date(2026, 8, 14))],
            records: [record(date(2026, 8, 12))],
            lastMenstrualPeriod: lmp,
            today: date(2026, 8, 14)
        )
        let current = weeks.first { $0.week == 18 }
        XCTAssertEqual(current?.entries.count, 2)
        if case .record = current?.entries.first {} else { XCTFail("记录应排在前面") }
    }

    func testTaskWithoutAnyDateFallsIntoCurrentWeek() {
        let lmp = date(2026, 4, 7)
        let weeks = TimelineBuilder.build(
            tasks: [task("无日期", due: nil)],
            records: [],
            lastMenstrualPeriod: lmp,
            today: date(2026, 8, 14)
        )
        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(weeks.first?.week, 18)
    }

    func testMarksWeekPositionRelativeToToday() {
        let lmp = date(2026, 4, 7)
        let weeks = TimelineBuilder.build(
            tasks: [
                task("过去", due: date(2026, 8, 5)),
                task("现在", due: date(2026, 8, 14)),
                task("未来", due: date(2026, 8, 20))
            ],
            records: [],
            lastMenstrualPeriod: lmp,
            today: date(2026, 8, 14)
        )
        XCTAssertEqual(weeks.map(\.position), [.past, .current, .future])
        XCTAssertEqual(weeks.map(\.week), [17, 18, 19])
    }

    func testCurrentWeekIsAlwaysPresentEvenWhenEmpty() {
        let lmp = date(2026, 4, 7)
        let weeks = TimelineBuilder.build(
            tasks: [], records: [], lastMenstrualPeriod: lmp, today: date(2026, 8, 14)
        )
        XCTAssertEqual(weeks.map(\.week), [18])
        XCTAssertTrue(weeks[0].entries.isEmpty)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppTests/TimelineBuilderTests`

Expected: 编译失败，`cannot find 'TimelineBuilder' in scope`

- [ ] **Step 3: 实现模型**

创建 `apps/ios/AimApp/Features/Timeline/TimelineModels.swift`：

```swift
import Foundation

enum TimelineEntry: Identifiable, Equatable {
    case task(TaskItem)
    case record(RecordItem)

    var id: String {
        switch self {
        case let .task(item): return "task-\(item.id.uuidString)"
        case let .record(item): return "record-\(item.id.uuidString)"
        }
    }

    var date: Date? {
        switch self {
        case let .task(item): return item.dueAt ?? item.scheduledFor
        case let .record(item): return item.occurredAt
        }
    }
}

struct TimelineWeek: Identifiable, Equatable {
    enum Position: Equatable {
        case past
        case current
        case future
    }

    let week: Int
    let startDate: Date
    let endDate: Date
    let position: Position
    let entries: [TimelineEntry]

    var id: Int { week }

    var openTaskCount: Int {
        entries.reduce(into: 0) { count, entry in
            if case let .task(item) = entry, item.isOpen { count += 1 }
        }
    }
}
```

- [ ] **Step 4: 实现分组器**

创建 `apps/ios/AimApp/Features/Timeline/TimelineBuilder.swift`：

```swift
import Foundation

enum TimelineBuilder {
    static var calendar: Calendar { PregnancyDateCalculator.calendar }

    static func lastMenstrualPeriod(asOf: Date, weeks: Int, days: Int) -> Date {
        calendar.date(byAdding: .day, value: -(weeks * 7 + days), to: asOf) ?? asOf
    }

    static func week(for date: Date, lastMenstrualPeriod: Date) -> Int {
        let start = calendar.startOfDay(for: lastMenstrualPeriod)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        return days / 7
    }

    static func startDate(ofWeek week: Int, lastMenstrualPeriod: Date) -> Date {
        let start = calendar.startOfDay(for: lastMenstrualPeriod)
        return calendar.date(byAdding: .day, value: week * 7, to: start) ?? start
    }

    static func build(
        tasks: [TaskItem],
        records: [RecordItem],
        lastMenstrualPeriod: Date,
        today: Date
    ) -> [TimelineWeek] {
        let currentWeek = week(for: today, lastMenstrualPeriod: lastMenstrualPeriod)

        var buckets: [Int: [TimelineEntry]] = [currentWeek: []]

        for task in tasks {
            let entry = TimelineEntry.task(task)
            let bucket = entry.date.map { week(for: $0, lastMenstrualPeriod: lastMenstrualPeriod) } ?? currentWeek
            buckets[bucket, default: []].append(entry)
        }

        for record in records {
            let entry = TimelineEntry.record(record)
            let bucket = week(for: record.occurredAt, lastMenstrualPeriod: lastMenstrualPeriod)
            buckets[bucket, default: []].append(entry)
        }

        return buckets.keys.sorted().map { weekNumber in
            let start = startDate(ofWeek: weekNumber, lastMenstrualPeriod: lastMenstrualPeriod)
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let position: TimelineWeek.Position = weekNumber < currentWeek
                ? .past
                : (weekNumber == currentWeek ? .current : .future)
            let sorted = (buckets[weekNumber] ?? []).sorted {
                ($0.date ?? start) < ($1.date ?? start)
            }
            return TimelineWeek(
                week: weekNumber,
                startDate: start,
                endDate: end,
                position: position,
                entries: sorted
            )
        }
    }
}
```

- [ ] **Step 5: 注册到 pbxproj**

在 `apps/ios/AimApp.xcodeproj/project.pbxproj` 中添加：

PBXFileReference 段（模仿第 90 行 `AgentChatAdapter.swift` 的格式）：

```
		A10000000000000000000041 /* TimelineModels.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Features/Timeline/TimelineModels.swift; sourceTree = "<group>"; };
		A10000000000000000000042 /* TimelineBuilder.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Features/Timeline/TimelineBuilder.swift; sourceTree = "<group>"; };
		A10000000000000000000043 /* TimelineBuilderTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/TimelineBuilderTests.swift; sourceTree = "<group>"; };
```

PBXBuildFile 段：

```
		A20000000000000000000042 /* TimelineModels.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10000000000000000000041 /* TimelineModels.swift */; };
		A20000000000000000000043 /* TimelineBuilder.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10000000000000000000042 /* TimelineBuilder.swift */; };
		A20000000000000000000044 /* TimelineBuilderTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = A10000000000000000000043 /* TimelineBuilderTests.swift */; };
```

新建 Timeline PBXGroup，并加入根组 `A40000000000000000000001` 的 children：

```
		A40000000000000000000103 = {isa = PBXGroup; children = (A10000000000000000000041, A10000000000000000000042); name = Timeline; sourceTree = "<group>"; };
```

把 `A10000000000000000000043` 加入 Tests 组 `A40000000000000000000014` 的 children。

把 `A20000000000000000000042`、`A20000000000000000000043` 加入主 target Sources 阶段 `A30000000000000000000001` 的 files；把 `A20000000000000000000044` 加入测试 target Sources 阶段 `A30000000000000000000002` 的 files。

- [ ] **Step 6: 运行测试确认通过**

Run: `xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppTests/TimelineBuilderTests`

Expected: 6 个测试全部 PASS

若测试未运行（0 tests executed），说明 pbxproj 注册漏了 —— 回到 Step 5 检查三处条目。

- [ ] **Step 7: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): add pregnancy timeline grouping"
```

---

### Task 3: 设计 token 层

把 4 个散装 `Color` 升级为 16 个带深色外观的 colorset，并建立字阶与几何常量。

**Files:**
- Create: `apps/ios/AimApp/Resources/Assets.xcassets/Aim/` 下 16 个 `.colorset/Contents.json`
- Rewrite: `apps/ios/AimApp/Core/DesignSystem/AimTheme.swift`
- Create: `apps/ios/AimApp/Core/DesignSystem/AimMetrics.swift`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `Color.aimCanvas` / `aimSurface` / `aimSurfaceRaised` / `aimSurfaceSunken` / `aimSeparator` / `aimRail` / `aimTextPrimary` / `aimTextSecondary` / `aimTextTertiary` / `aimTextOnAccent` / `aimAccent` / `aimAccentSoft` / `aimSuccess` / `aimSuccessSoft` / `aimDanger` / `aimDangerSoft`；`enum AimMetrics`；`aimCard()` 修饰符

- [ ] **Step 1: 建 colorset**

对下表每一行，创建 `apps/ios/AimApp/Resources/Assets.xcassets/Aim/<名称>.colorset/Contents.json`。

| 名称 | Light | Dark |
| --- | --- | --- |
| `AimCanvas` | `#F6F1E9` | `#1A1714` |
| `AimSurface` | `#FFFDF9` | `#232019` |
| `AimSurfaceRaised` | `#FFFFFF` | `#2C2822` |
| `AimSurfaceSunken` | `#F8F3EA` | `#1F1C17` |
| `AimSeparator` | `#EBE3D6` | `#38322A` |
| `AimRail` | `#DFD6C6` | `#443D33` |
| `AimTextPrimary` | `#2C2620` | `#F0EAE0` |
| `AimTextSecondary` | `#837A6E` | `#A79D8F` |
| `AimTextTertiary` | `#ABA192` | `#7A7164` |
| `AimTextOnAccent` | `#FFF8F3` | `#FFF8F3` |
| `AimAccent` | `#BC5F3A` | `#D97D52` |
| `AimAccentSoft` | `#F5E5DC` | `#3A2A21` |
| `AimSuccess` | `#6B7F4E` | `#9BB07A` |
| `AimSuccessSoft` | `#EDF0E6` | `#2A3020` |
| `AimDanger` | `#B4442F` | `#E08066` |
| `AimDangerSoft` | `#F7E6E1` | `#3A241D` |

模板（以 `AimCanvas` 为例，其余替换两个 hex）：

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "red" : "0xF6", "green" : "0xF1", "blue" : "0xE9" }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "red" : "0x1A", "green" : "0x17", "blue" : "0x14" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "aim", "version" : 1 }
}
```

再创建分组文件 `apps/ios/AimApp/Resources/Assets.xcassets/Aim/Contents.json`：

```json
{ "info" : { "author" : "aim", "version" : 1 }, "properties" : { "provides-namespace" : false } }
```

- [ ] **Step 2: 把 AccentColor 同步为陶土色**

覆写 `apps/ios/AimApp/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`，使其与 `AimAccent` 完全一致（light `#BC5F3A`，dark `#D97D52`）。系统控件的 tint 由它决定，必须与设计 token 一致。

- [ ] **Step 3: 重写 AimTheme**

用以下内容完全替换 `apps/ios/AimApp/Core/DesignSystem/AimTheme.swift`：

```swift
import SwiftUI

extension Color {
    static let aimCanvas = Color("AimCanvas")
    static let aimSurface = Color("AimSurface")
    static let aimSurfaceRaised = Color("AimSurfaceRaised")
    static let aimSurfaceSunken = Color("AimSurfaceSunken")
    static let aimSeparator = Color("AimSeparator")
    static let aimRail = Color("AimRail")
    static let aimTextPrimary = Color("AimTextPrimary")
    static let aimTextSecondary = Color("AimTextSecondary")
    static let aimTextTertiary = Color("AimTextTertiary")
    static let aimTextOnAccent = Color("AimTextOnAccent")
    static let aimAccent = Color("AimAccent")
    static let aimAccentSoft = Color("AimAccentSoft")
    static let aimSuccess = Color("AimSuccess")
    static let aimSuccessSoft = Color("AimSuccessSoft")
    static let aimDanger = Color("AimDanger")
    static let aimDangerSoft = Color("AimDangerSoft")
}

struct AimCard: ViewModifier {
    var radius: CGFloat = AimMetrics.radiusCard

    func body(content: Content) -> some View {
        content
            .padding(AimMetrics.space16)
            .background(Color.aimSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.aimSeparator, lineWidth: 1)
            }
    }
}

extension View {
    func aimCard(radius: CGFloat = AimMetrics.radiusCard) -> some View {
        modifier(AimCard(radius: radius))
    }

    func aimLabelStyle() -> some View {
        font(.caption2)
            .tracking(0.9)
            .foregroundStyle(Color.aimTextTertiary)
    }
}
```

- [ ] **Step 4: 建几何常量**

创建 `apps/ios/AimApp/Core/DesignSystem/AimMetrics.swift`：

```swift
import CoreGraphics

enum AimMetrics {
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space28: CGFloat = 28

    static let radiusButton: CGFloat = 13
    static let radiusToast: CGFloat = 15
    static let radiusDiffCard: CGFloat = 16
    static let radiusCard: CGFloat = 20
    static let radiusSheet: CGFloat = 28

    static let railInset: CGFloat = 27
    static let railWidth: CGFloat = 1
    static let railDotSize: CGFloat = 9
    static let railDotStroke: CGFloat = 1.5
    static let railAnchorSize: CGFloat = 13
    static let railAnchorHalo: CGFloat = 4
    static let rowLeadingInset: CGFloat = 52

    static let circleButtonSize: CGFloat = 32
    static let checkboxSize: CGFloat = 18
}
```

- [ ] **Step 5: 迁移旧色名**

Run: `grep -rn "aimWarmBackground\|aimWarmSurface\|aimSoftRose\|aimSoftSand\|aimWarmCard" apps/ios/AimApp --include="*.swift"`

逐处替换：`aimWarmBackground` → `aimCanvas`，`aimWarmSurface` → `aimSurface`，`aimSoftRose` → `aimDangerSoft`，`aimSoftSand` → `aimAccentSoft`，`.aimWarmCard()` → `.aimCard()`。

- [ ] **Step 6: 注册 AimMetrics.swift 到 pbxproj**

按 Task 2 Step 5 的同样三处流程注册，ID 用 `A10000000000000000000044` / `A20000000000000000000045`，加入 Core 组 `A40000000000000000000003`。Assets 目录已在工程中，新增的 colorset 不需要单独注册。

- [ ] **Step 7: 编译验证**

Run: `make ios-build`
Expected: BUILD SUCCEEDED，无 `cannot find 'aimWarmBackground'` 一类错误

- [ ] **Step 8: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): establish design token layer with dark appearance"
```

---

### Task 4: 时间线基础组件

导轨、孕周头、任务行、记录行、来源标记。

**Files:**
- Create: `apps/ios/AimApp/Core/DesignSystem/Components/AimTimelineRail.swift`
- Create: `apps/ios/AimApp/Core/DesignSystem/Components/AimWeekHeader.swift`
- Create: `apps/ios/AimApp/Core/DesignSystem/Components/AimTimelineRows.swift`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TimelineWeek.Position`（Task 2）、`AimMetrics`、颜色 token（Task 3）、`TaskItem.isAgentChanged`（Task 1）
- Produces:
  - `AimTimelineRail(position:showsDot:isAnchor:)` — 供 `.listRowBackground` 使用
  - `AimWeekHeader(week:startDate:endDate:position:count:)`
  - `AimTaskRow(task:assigneeName:onToggle:)`
  - `AimRecordRow(record:)`
  - `AimSourceBadge()`

- [ ] **Step 1: 实现导轨**

创建 `apps/ios/AimApp/Core/DesignSystem/Components/AimTimelineRail.swift`：

```swift
import SwiftUI

struct AimTimelineRail: View {
    let position: TimelineWeek.Position
    var showsDot: Bool = false

    private var isFuture: Bool { position == .future }
    private var isAnchor: Bool { position == .current && showsDot }

    var body: some View {
        ZStack(alignment: .top) {
            Color.aimCanvas

            HStack(spacing: 0) {
                line
                    .frame(width: AimMetrics.railWidth)
                    .padding(.leading, AimMetrics.railInset)
                Spacer(minLength: 0)
            }

            if showsDot {
                HStack(spacing: 0) {
                    dot.padding(.leading, dotLeadingInset)
                    Spacer(minLength: 0)
                }
                .padding(.top, AimMetrics.space4)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var line: some View {
        if isFuture {
            DashedLine().stroke(Color.aimRail, style: StrokeStyle(lineWidth: AimMetrics.railWidth, dash: [3, 3]))
        } else {
            Color.aimRail
        }
    }

    @ViewBuilder
    private var dot: some View {
        if isAnchor {
            Circle()
                .fill(Color.aimAccent)
                .frame(width: AimMetrics.railAnchorSize, height: AimMetrics.railAnchorSize)
                .overlay {
                    Circle().stroke(Color.aimAccentSoft, lineWidth: AimMetrics.railAnchorHalo)
                }
        } else {
            Circle()
                .fill(Color.aimCanvas)
                .frame(width: AimMetrics.railDotSize, height: AimMetrics.railDotSize)
                .overlay {
                    Circle().stroke(Color.aimRail, lineWidth: AimMetrics.railDotStroke)
                }
        }
    }

    private var dotLeadingInset: CGFloat {
        let size = isAnchor ? AimMetrics.railAnchorSize : AimMetrics.railDotSize
        return AimMetrics.railInset - size / 2
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
```

- [ ] **Step 2: 实现孕周头**

创建 `apps/ios/AimApp/Core/DesignSystem/Components/AimWeekHeader.swift`：

```swift
import SwiftUI

struct AimWeekHeader: View {
    let week: Int
    let startDate: Date
    let endDate: Date
    let position: TimelineWeek.Position
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption2)
                .tracking(0.9)
                .foregroundStyle(position == .current ? Color.aimAccent : Color.aimTextTertiary)
            Spacer(minLength: AimMetrics.space8)
            if count > 0 {
                Text("\(count) 项")
                    .font(.caption2)
                    .foregroundStyle(Color.aimTextTertiary)
            }
        }
        .padding(.vertical, AimMetrics.space8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timeline-week-header-\(week)")
    }

    private var title: String {
        if position == .current { return "今天" }
        return "孕 \(week) 周 · \(range)"
    }

    private var range: String {
        let formatter = DateFormatter()
        formatter.calendar = PregnancyDateCalculator.calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: startDate) + "–" + formatter.string(from: endDate)
    }
}
```

- [ ] **Step 3: 实现任务行、记录行、来源标记**

创建 `apps/ios/AimApp/Core/DesignSystem/Components/AimTimelineRows.swift`：

```swift
import SwiftUI

struct AimSourceBadge: View {
    var body: some View {
        Text("Agent 调整")
            .font(.footnote)
            .foregroundStyle(Color.aimAccent)
    }
}

struct AimTaskRow: View {
    let task: TaskItem
    var assigneeName: String?
    var onToggle: (() -> Void)?

    private var isDone: Bool { task.status == .completed }

    var body: some View {
        HStack(alignment: .top, spacing: AimMetrics.space12) {
            Button { onToggle?() } label: { checkbox }
                .buttonStyle(.plain)
                .disabled(onToggle == nil)
                .accessibilityLabel(isDone ? "已完成" : "未完成")

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
        if isDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(Color.aimSuccess)
        } else {
            Circle()
                .stroke(Color.aimRail, lineWidth: AimMetrics.railDotStroke)
                .frame(width: AimMetrics.checkboxSize, height: AimMetrics.checkboxSize)
        }
    }

    @ViewBuilder
    private var meta: some View {
        let parts = metaParts
        if !parts.isEmpty || task.isAgentChanged {
            HStack(spacing: AimMetrics.space4) {
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Color.aimTextSecondary)
                }
                if task.isAgentChanged {
                    if !parts.isEmpty {
                        Text("·").font(.footnote).foregroundStyle(Color.aimTextSecondary)
                    }
                    AimSourceBadge()
                }
            }
        }
    }

    private var metaParts: [String] {
        var parts: [String] = []
        if let assigneeName { parts.append(assigneeName) }
        if let date = task.dueAt ?? task.scheduledFor {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        return parts
    }
}

struct AimRecordRow: View {
    let record: RecordItem

    var body: some View {
        HStack(alignment: .top, spacing: AimMetrics.space12) {
            Image(systemName: record.type.symbolName)
                .font(.body)
                .foregroundStyle(Color.aimAccent)
                .frame(width: AimMetrics.checkboxSize)

            VStack(alignment: .leading, spacing: AimMetrics.space4) {
                Text(record.displayTitle)
                    .font(.body)
                    .foregroundStyle(Color.aimTextPrimary)
                Text("\(record.type.displayName) · \(record.displaySummary)")
                    .font(.footnote)
                    .foregroundStyle(Color.aimTextSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AimMetrics.space8)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 4: 注册到 pbxproj**

新建 Components 组 `A40000000000000000000104`（加入根组 children），三个文件用 ID `A10000000000000000000045`–`A10000000000000000000047`，BuildFile 用 `A20000000000000000000046`–`A20000000000000000000048`，全部加入主 target Sources 阶段。

- [ ] **Step 5: 编译验证**

Run: `make ios-build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): add timeline rail and row components"
```

---

### Task 5: TimelineStore

合并加载任务与记录，暴露分组结果、筛选与状态。

**Files:**
- Create: `apps/ios/AimApp/Features/Timeline/TimelineStore.swift`
- Create: `apps/ios/AimApp/Tests/TimelineStoreTests.swift`
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `BusinessRepositoryProtocol` 的 `fetchToday()` / `fetchPlan()` / `fetchRecords(type:)` / `fetchFamily()`，返回 `TodaySnapshot` / `PlanSnapshot` / `RecordSnapshot` / `FamilySnapshot`（注意是 `RecordSnapshot`，无复数 s）
- Produces: `@Observable @MainActor final class TimelineStore`，成员 `weeks: [TimelineWeek]`、`filter: TimelineFilter`、`isLoading: Bool`、`errorMessage: String?`、`currentWeek: Int?`、`focusTask: TaskItem?`、`assigneeName(for:) -> String?`、`load()`、`toggle(_:)`
- Produces: `enum TimelineFilter: CaseIterable { case all, tasks, checkup, symptom, note }`，含 `displayName`

- [ ] **Step 1: 写失败测试**

创建 `apps/ios/AimApp/Tests/TimelineStoreTests.swift`：

```swift
import XCTest
@testable import AimApp

@MainActor
final class TimelineStoreTests: XCTestCase {
    func testFilterAllKeepsTasksAndRecords() {
        XCTAssertTrue(TimelineFilter.all.accepts(entryKind: .task))
        XCTAssertTrue(TimelineFilter.all.accepts(entryKind: .record(.checkup)))
    }

    func testFilterTasksExcludesRecords() {
        XCTAssertTrue(TimelineFilter.tasks.accepts(entryKind: .task))
        XCTAssertFalse(TimelineFilter.tasks.accepts(entryKind: .record(.note)))
    }

    func testFilterCheckupOnlyAcceptsCheckupRecords() {
        XCTAssertFalse(TimelineFilter.checkup.accepts(entryKind: .task))
        XCTAssertTrue(TimelineFilter.checkup.accepts(entryKind: .record(.checkup)))
        XCTAssertFalse(TimelineFilter.checkup.accepts(entryKind: .record(.symptom)))
    }

    func testFocusTaskPrefersEarliestOpenTaskInCurrentWeek() {
        let store = TimelineStore.preview()
        XCTAssertEqual(store.focusTask?.title, "核对检查所需材料")
    }

    func testAssigneeNameResolvesFromFamilyMembers() {
        let store = TimelineStore.preview()
        let motherID = store.familyMembers.first { $0.role == .mother }?.accountID
        XCTAssertEqual(store.assigneeName(for: motherID), "妈妈")
        XCTAssertNil(store.assigneeName(for: nil))
        XCTAssertNil(store.assigneeName(for: UUID()))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppTests/TimelineStoreTests`

Expected: `cannot find 'TimelineFilter' in scope`

- [ ] **Step 3: 实现**

创建 `apps/ios/AimApp/Features/Timeline/TimelineStore.swift`：

```swift
import Foundation
import Observation

enum TimelineEntryKind: Equatable {
    case task
    case record(RecordType)
}

enum TimelineFilter: String, CaseIterable, Hashable {
    case all
    case tasks
    case checkup
    case symptom
    case note

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .tasks: return "待办"
        case .checkup: return "产检"
        case .symptom: return "身体感受"
        case .note: return "随手记"
        }
    }

    func accepts(entryKind: TimelineEntryKind) -> Bool {
        switch (self, entryKind) {
        case (.all, _): return true
        case (.tasks, .task): return true
        case (.tasks, .record): return false
        case (_, .task): return false
        case let (.checkup, .record(type)): return type == .checkup
        case let (.symptom, .record(type)): return type == .symptom
        case let (.note, .record(type)): return type == .note
        }
    }
}

@MainActor
@Observable
final class TimelineStore {
    var weeks: [TimelineWeek] = []
    var filter: TimelineFilter = .all { didSet { rebuild() } }
    var isLoading = false
    var errorMessage: String?
    var familyMembers: [FamilyMember] = []

    var repository: BusinessRepositoryProtocol?

    private var tasks: [TaskItem] = []
    private var records: [RecordItem] = []
    private var lastMenstrualPeriod: Date?
    private var today: Date = .now

    var currentWeek: Int? {
        weeks.first { $0.position == .current }?.week
    }

    var focusTask: TaskItem? {
        guard let current = weeks.first(where: { $0.position == .current }) else { return nil }
        return current.entries.compactMap { entry -> TaskItem? in
            if case let .task(item) = entry, item.isOpen { return item }
            return nil
        }.first
    }

    func assigneeName(for memberID: UUID?) -> String? {
        guard let memberID else { return nil }
        return familyMembers.first { $0.accountID == memberID }?.role.displayName
    }

    func load() async {
        guard let repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let todaySnapshot = try await repository.fetchToday()
            let plan = try await repository.fetchPlan()
            let recordsSnapshot = try await repository.fetchRecords(type: nil)
            let family = try await repository.fetchFamily()

            today = todaySnapshot.asOf
            lastMenstrualPeriod = TimelineBuilder.lastMenstrualPeriod(
                asOf: todaySnapshot.asOf,
                weeks: todaySnapshot.weeks,
                days: todaySnapshot.days
            )
            tasks = plan.tasks
            records = recordsSnapshot.records
            familyMembers = family.members
            errorMessage = nil
            rebuild()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rebuild() {
        guard let lastMenstrualPeriod else { return }
        let filteredTasks = filter.accepts(entryKind: .task) ? tasks : []
        let filteredRecords = records.filter { filter.accepts(entryKind: .record($0.type)) }
        weeks = TimelineBuilder.build(
            tasks: filteredTasks,
            records: filteredRecords,
            lastMenstrualPeriod: lastMenstrualPeriod,
            today: today
        )
    }
}
```

- [ ] **Step 4: 加 preview 工厂**

在 `TimelineStore` 中追加（供测试与 Xcode 预览使用）：

```swift
extension TimelineStore {
    static func preview() -> TimelineStore {
        let store = TimelineStore()
        let calendar = PregnancyDateCalculator.calendar
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 9))!
        let motherID = UUID()
        store.familyMembers = [
            FamilyMember(accountID: motherID, role: .mother, status: "active", joinedAt: nil),
            FamilyMember(accountID: UUID(), role: .father, status: "active", joinedAt: nil)
        ]
        store.tasks = [
            TaskItem(id: UUID(), title: "核对检查所需材料", detail: "检查日期确定后，需要提前核对证件和既往资料。",
                     status: .todo, version: 1,
                     dueAt: calendar.date(byAdding: .hour, value: 1, to: today), scheduledFor: nil,
                     assignedMemberID: motherID, changedByActor: .agent),
            TaskItem(id: UUID(), title: "晚饭后散步 20 分钟", detail: nil, status: .todo, version: 1,
                     dueAt: calendar.date(byAdding: .hour, value: 10, to: today), scheduledFor: nil,
                     assignedMemberID: motherID, changedByActor: .system)
        ]
        store.records = []
        store.today = today
        store.lastMenstrualPeriod = TimelineBuilder.lastMenstrualPeriod(asOf: today, weeks: 18, days: 3)
        store.rebuild()
        return store
    }
}
```

注意：`tasks`、`records`、`today`、`lastMenstrualPeriod`、`rebuild()` 为 `private`。把它们改为 `private(set)` 并把 `rebuild()` 改为 `fileprivate` 无法跨扩展访问 —— 直接把这五个成员的访问级别改为 `internal`（去掉 `private`），保持简单。

- [ ] **Step 5: 注册到 pbxproj 并运行测试**

按既有流程注册两个新文件（源文件入主 target，测试文件入 `AimAppTests`）。

Run: `xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppTests/TimelineStoreTests`

Expected: 5 个测试全部 PASS

- [ ] **Step 6: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): add timeline store with filtering"
```

---

### Task 6: TimelineView 与三 Tab 导航

**Files:**
- Create: `apps/ios/AimApp/Features/Timeline/TimelineView.swift`
- Create: `apps/ios/AimApp/Core/DesignSystem/Components/AimFocusCard.swift`
- Modify: `apps/ios/AimApp/App/AimApp.swift`
- Delete: `apps/ios/AimApp/Features/Today/TodayView.swift` 中的 `TodayView`（保留 `PregnancySetupView`、`PregnancyDateMode`、`PregnancyDateCalculator`、`TaskRow`）
- Delete: `apps/ios/AimApp/Features/Plan/PlanView.swift`、`apps/ios/AimApp/Features/Records/RecordsView.swift` 中的 `RecordsView`（保留文件末尾的 `RecordType` / `RecordVisibility` / `RecordItem` 扩展）

**Interfaces:**
- Consumes: `TimelineStore`（Task 5）、`AimTimelineRail` / `AimWeekHeader` / `AimTaskRow` / `AimRecordRow`（Task 4）
- Produces: `TimelineView(store:planStore:recordStore:)`、`AimFocusCard(task:actionTitle:onAction:)`

- [ ] **Step 1: 实现焦点卡**

创建 `apps/ios/AimApp/Core/DesignSystem/Components/AimFocusCard.swift`：

```swift
import SwiftUI

struct AimFocusCard: View {
    let task: TaskItem
    var actionTitle: String = "开始处理"
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Text("现在最重要").aimLabelStyle()
            Text(task.title)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.aimTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = task.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.aimTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onAction) {
                Text(actionTitle)
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AimMetrics.space12)
                    .background(Color.aimAccent, in: RoundedRectangle(cornerRadius: AimMetrics.radiusButton, style: .continuous))
                    .foregroundStyle(Color.aimTextOnAccent)
            }
            .buttonStyle(.plain)
            .padding(.top, AimMetrics.space4)
        }
        .aimCard()
        .accessibilityIdentifier("timeline-focus-card")
    }
}
```

- [ ] **Step 2: 实现时间线视图**

本步先用系统 `navigationTitle` + `toolbar` 让页面跑起来；Task 12 Step 1 会把它换成规格 §5.6 的自定义头部。`showsBackToToday` 在本步只声明不驱动，Task 12 Step 4 补上触发条件 —— 在此之前「回到今天」不会出现，属预期。

创建 `apps/ios/AimApp/Features/Timeline/TimelineView.swift`：

```swift
import SwiftUI

struct TimelineView: View {
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: TimelineStore
    let planStore: PlanStore
    let recordStore: RecordStore

    @State private var showingComposer = false
    @State private var showingAgent = false
    @State private var showingPregnancySetup = false
    @State private var showsBackToToday = false

    private let todayAnchor = "timeline-today"

    var body: some View {
        NavigationStack {
            Group {
                if session.pregnancyID == nil {
                    setupPrompt
                } else if store.weeks.isEmpty, store.isLoading {
                    ProgressView("正在整理孕期时间线")
                } else if store.weeks.isEmpty, let message = store.errorMessage {
                    AimErrorState(message: message) { Task { await store.load() } }
                } else {
                    timeline
                }
            }
            .background(Color.aimCanvas)
            .navigationTitle(navigationTitle)
            .toolbar { toolbar }
            .refreshable { await store.load() }
            .task(id: session.pregnancyID) {
                guard session.pregnancyID != nil, store.weeks.isEmpty else { return }
                await store.load()
            }
            .sheet(isPresented: $showingComposer) {
                RecordComposerView(store: recordStore) {
                    showingComposer = false
                    Task { await store.load() }
                }
            }
            .sheet(isPresented: $showingPregnancySetup) { PregnancySetupView() }
            .fullScreenCover(isPresented: $showingAgent) {
                AgentSheet(context: agentContext)
            }
        }
    }

    private var navigationTitle: String {
        guard let week = store.currentWeek else { return "孕期" }
        return "孕 \(week) 周"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("筛选", selection: $store.filter) {
                    ForEach(TimelineFilter.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .accessibilityIdentifier("timeline-filter")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("新增记录", systemImage: "plus") { showingComposer = true }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("问一问", systemImage: "wand.and.sparkles") { showingAgent = true }
                .accessibilityIdentifier("global-agent-button")
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(store.weeks) { week in
                    Section {
                        rows(for: week)
                    } header: {
                        AimWeekHeader(week: week.week, startDate: week.startDate, endDate: week.endDate,
                                      position: week.position, count: week.entries.count)
                            .listRowInsets(EdgeInsets(top: 0, leading: AimMetrics.rowLeadingInset,
                                                      bottom: 0, trailing: AimMetrics.space16))
                            .listRowBackground(AimTimelineRail(position: week.position, showsDot: true))
                            .id(week.position == .current ? todayAnchor : "week-\(week.week)")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.aimCanvas)
            .safeAreaInset(edge: .bottom) {
                if showsBackToToday { backToToday(proxy) }
            }
            .task {
                proxy.scrollTo(todayAnchor, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func rows(for week: TimelineWeek) -> some View {
        if week.position == .current, let focus = store.focusTask {
            AimFocusCard(task: focus) { showingAgent = true }
                .listRowInsets(EdgeInsets(top: AimMetrics.space8, leading: AimMetrics.rowLeadingInset,
                                          bottom: AimMetrics.space12, trailing: AimMetrics.space16))
                .listRowSeparator(.hidden)
                .listRowBackground(AimTimelineRail(position: week.position))
                .accessibilityIdentifier("timeline-today-anchor")
        }

        ForEach(entries(in: week)) { entry in
            row(entry)
                .listRowInsets(EdgeInsets(top: 0, leading: AimMetrics.rowLeadingInset,
                                          bottom: 0, trailing: AimMetrics.space16))
                .listRowSeparator(.hidden)
                .listRowBackground(AimTimelineRail(position: week.position))
        }
    }

    private func entries(in week: TimelineWeek) -> [TimelineEntry] {
        guard week.position == .current, let focus = store.focusTask else { return week.entries }
        return week.entries.filter { $0.id != TimelineEntry.task(focus).id }
    }

    @ViewBuilder
    private func row(_ entry: TimelineEntry) -> some View {
        switch entry {
        case let .task(task):
            NavigationLink {
                TaskDetailView(task: task, repository: planStore.repository)
            } label: {
                AimTaskRow(task: task, assigneeName: store.assigneeName(for: task.assignedMemberID))
            }
        case let .record(record):
            NavigationLink {
                RecordDetailView(record: record, store: recordStore, planStore: planStore)
            } label: {
                AimRecordRow(record: record)
            }
        }
    }

    private func backToToday(_ proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation { proxy.scrollTo(todayAnchor, anchor: .top) }
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

    private var setupPrompt: some View {
        AimEmptyState(
            title: "先补充孕期信息",
            message: "有了预产期或末次月经，Aim 才能把计划和记录放进正确的孕周。",
            actionTitle: "补充孕期信息"
        ) { showingPregnancySetup = true }
    }

    private var agentContext: AgentContext {
        let week = store.currentWeek.map { "孕 \($0) 周" } ?? "孕期"
        var lines = [week]
        if let focus = store.focusTask { lines.append("当前最重要：" + focus.title) }
        return AgentContext(title: "孕期", summary: lines.joined(separator: "\n"))
    }
}
```

- [ ] **Step 3: 补空态与错误态组件**

创建 `apps/ios/AimApp/Core/DesignSystem/Components/AimStateViews.swift`：

```swift
import SwiftUI

struct AimEmptyState: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Text(title).font(.title3.weight(.medium))
        } description: {
            Text(message).foregroundStyle(Color.aimTextSecondary)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.aimAccent)
            }
        }
    }
}

struct AimErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("暂时加载不出来", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message).foregroundStyle(Color.aimTextSecondary)
        } actions: {
            Button("重试", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(Color.aimAccent)
        }
        .accessibilityIdentifier("error-state")
    }
}
```

- [ ] **Step 4: 改导航为三 Tab**

把 `apps/ios/AimApp/App/AimApp.swift` 的 `MainTabView` 替换为：

```swift
private struct MainTabView: View {
    @Environment(AppSessionStore.self) private var session
    @State private var timelineStore = TimelineStore()
    @State private var planStore = PlanStore()
    @State private var recordStore = RecordStore()
    @State private var familyStore = FamilyStore()
    @State private var selectedTab: AimTab = .timeline

    var body: some View {
        TabView(selection: $selectedTab) {
            TimelineView(store: timelineStore, planStore: planStore, recordStore: recordStore)
                .tabItem { Label("孕期", systemImage: "timeline.selection") }
                .tag(AimTab.timeline)

            AgentSheet(context: nil)
                .tabItem { Label("Agent", systemImage: "wand.and.sparkles") }
                .tag(AimTab.agent)

            FamilyView(store: familyStore)
                .tabItem { Label("家庭", systemImage: "person.2") }
                .tag(AimTab.family)
        }
        .task { await reloadRepositories() }
        .onChange(of: session.pregnancyID) { _, _ in
            Task { await reloadRepositories() }
        }
    }

    private enum AimTab: Hashable {
        case timeline
        case agent
        case family
    }

    private func reloadRepositories() async {
        let repository = BusinessRepository(environment: session.environment)
        timelineStore.repository = repository
        planStore.repository = repository
        recordStore.repository = repository
        familyStore.repository = repository
        await timelineStore.load()
        await planStore.load()
        await recordStore.load()
        await familyStore.load()
    }
}
```

删除 `currentAgentContext` 计算属性与悬浮按钮 overlay。

- [ ] **Step 5: 删除被取代的视图**

- 从 `Features/Today/TodayView.swift` 删除 `struct TodayView` 与 `private struct PriorityTaskRow`，保留其余类型。
- 删除 `Features/Plan/PlanView.swift` 整个文件，并从 pbxproj 移除其三处条目。
- 从 `Features/Records/RecordsView.swift` 删除 `struct RecordsView` 与 `struct RecordRow`，保留文件末尾的三个 extension。
- `PlanStore` 与 `RecordStore` 保留 —— 时间线与详情页仍依赖它们。

- [ ] **Step 6: 更新受影响的测试**

Run: `grep -rn "TodayView\|PlanView\|RecordsView" apps/ios/AimApp --include="*.swift"`

`TodayStoreTests` 测的是 store 不是 view，应仍能通过。`CoreJourneyUITests` 中 `app.tabBars.buttons["今天"]` 改为 `["孕期"]`，`app.tabBars.buttons["记录"]` 相关步骤改为点击时间线工具栏的「新增记录」按钮。

- [ ] **Step 7: 编译并跑全部测试**

Run: `make ios-build && make ios-test`
Expected: BUILD SUCCEEDED，全部单元测试 PASS

- [ ] **Step 8: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): replace today/plan/records tabs with pregnancy timeline"
```

---

### Task 7: Toast 与撤销

**Files:**
- Create: `apps/ios/AimApp/Core/DesignSystem/Components/AimToast.swift`
- Modify: `apps/ios/AimApp/Features/Timeline/TimelineView.swift`

**Interfaces:**
- Produces: `struct AimToastMessage { let text: String; let undo: (() -> Void)? }`、`.aimToast(_ binding: Binding<AimToastMessage?>)` 视图修饰符

- [ ] **Step 1: 实现**

创建 `apps/ios/AimApp/Core/DesignSystem/Components/AimToast.swift`：

```swift
import SwiftUI

struct AimToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    var undoTitle: String = "撤销"
    var undo: (() -> Void)?

    static func == (lhs: AimToastMessage, rhs: AimToastMessage) -> Bool { lhs.id == rhs.id }
}

private struct AimToastModifier: ViewModifier {
    @Binding var message: AimToastMessage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                toast(message)
                    .padding(.horizontal, AimMetrics.space16)
                    .padding(.bottom, AimMetrics.space12)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: message.id) {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation { self.message = nil }
                    }
            }
        }
        .animation(.snappy, value: message)
    }

    private func toast(_ message: AimToastMessage) -> some View {
        HStack(spacing: AimMetrics.space12) {
            Image(systemName: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.aimSuccess)
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(Color.aimTextOnAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let undo = message.undo {
                Button(message.undoTitle) {
                    undo()
                    self.message = nil
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.aimAccent)
            }
            Button {
                self.message = nil
            } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .foregroundStyle(Color.aimTextTertiary)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, AimMetrics.space16)
        .padding(.vertical, AimMetrics.space12)
        .background(Color.aimTextPrimary, in: RoundedRectangle(cornerRadius: AimMetrics.radiusToast, style: .continuous))
        .accessibilityIdentifier("agent-undo-toast")
    }
}

extension View {
    func aimToast(_ message: Binding<AimToastMessage?>) -> some View {
        modifier(AimToastModifier(message: message))
    }
}
```

注意：toast 底色使用 `aimTextPrimary`（浅色下是暖黑、深色下是暖白），文字使用 `aimTextOnAccent`。深色模式下这会得到浅底深字 —— 这是刻意的，toast 在两种模式下都与页面形成反差。

- [ ] **Step 2: 接到时间线**

在 `TimelineView` 中加 `@State private var toast: AimToastMessage?`，在最外层 `Group` 后追加 `.aimToast($toast)`。

- [ ] **Step 3: 编译验证**

Run: `make ios-build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): add toast with undo affordance"
```

---

### Task 8: Agent 变更确认 sheet

**Files:**
- Create: `apps/ios/AimApp/Features/Agent/AgentChangePreview.swift`
- Create: `apps/ios/AimApp/Features/Agent/AgentDiffSheet.swift`
- Create: `apps/ios/AimApp/Tests/AgentChangePreviewTests.swift`
- Modify: `apps/ios/AimApp/Features/Agent/AgentSheet.swift`

**Interfaces:**
- Consumes: `EveInputRequest`（`Clients/EveClient/EveEvent.swift`）
- Produces: `struct AgentChangePreview { let understanding: String; let qualifier: String?; let changes: [AgentChangeRow] }`、`struct AgentChangeRow { let symbol: String; let field: String; let before: String?; let after: String }`、`AgentChangePreview.from(_ request: EveInputRequest) -> AgentChangePreview`、`AgentDiffSheet(preview:onApply:onDismiss:)`

- [ ] **Step 1: 写失败测试**

创建 `apps/ios/AimApp/Tests/AgentChangePreviewTests.swift`：

```swift
import XCTest
@testable import AimApp

final class AgentChangePreviewTests: XCTestCase {
    func testRendersBeforeAndAfterWithArrow() {
        let row = AgentChangeRow(symbol: "calendar", field: "检查日期", before: "今天", after: "8月19日")
        XCTAssertEqual(row.valueText, "今天 → 8月19日")
    }

    func testRendersOnlyAfterWhenBeforeIsMissing() {
        let row = AgentChangeRow(symbol: "person", field: "家庭分工", before: nil, after: "由爸爸负责")
        XCTAssertEqual(row.valueText, "由爸爸负责")
    }

    func testFallsBackToPromptWhenRequestHasNoStructuredChanges() {
        let request = EveInputRequest(requestID: "r1", kind: "approval", prompt: "要执行这项计划变更吗？",
                                      options: [], toolName: nil, changes: nil, qualifier: nil)
        let preview = AgentChangePreview.from(request)
        XCTAssertEqual(preview.understanding, "要执行这项计划变更吗？")
        XCTAssertTrue(preview.changes.isEmpty)
    }

    func testApplyButtonTitleCountsChanges() {
        let preview = AgentChangePreview(
            understanding: "医生把系统超声检查改到下周三",
            qualifier: "这是日程变化，不涉及新的医疗判断。",
            changes: [
                AgentChangeRow(symbol: "calendar", field: "检查日期", before: "今天", after: "8月19日"),
                AgentChangeRow(symbol: "arrow.clockwise", field: "材料准备", before: "8月20日", after: "8月18日")
            ]
        )
        XCTAssertEqual(preview.applyTitle, "应用 2 项变更")
    }

    func testApplyButtonTitleWithoutStructuredChanges() {
        let preview = AgentChangePreview(understanding: "问题", qualifier: nil, changes: [])
        XCTAssertEqual(preview.applyTitle, "确认执行")
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppTests/AgentChangePreviewTests`

Expected: `cannot find 'AgentChangeRow' in scope`

- [ ] **Step 3: 扩展 EveInputRequest**

打开 `apps/ios/AimApp/Clients/EveClient/EveEvent.swift`，为 `EveInputRequest` 增加两个可选字段（若 Eve 未下发则为 `nil`）：

```swift
    let changes: [EveChangeDTO]?
    let qualifier: String?
```

`EveInputRequest` 已声明 `Identifiable`（`var id: String { requestID }`），无需另加。

需要同步改三处：`CodingKeys` 增加 `changes`、`qualifier`；显式 `init` 增加这两个参数（现有签名为 `init(requestID:kind:prompt:options:toolName:)`）；以及自定义 `init(from:)`（若存在）中用 `decodeIfPresent` 解出这两个字段。

再新增：

```swift
struct EveChangeDTO: Decodable, Sendable {
    let field: String
    let before: String?
    let after: String
    let symbol: String?
}
```

- [ ] **Step 4: 实现 preview 模型**

创建 `apps/ios/AimApp/Features/Agent/AgentChangePreview.swift`：

```swift
import Foundation

struct AgentChangeRow: Identifiable, Equatable {
    var id: String { field + after }
    let symbol: String
    let field: String
    let before: String?
    let after: String

    var valueText: String {
        guard let before, !before.isEmpty else { return after }
        return "\(before) → \(after)"
    }
}

struct AgentChangePreview: Equatable {
    let understanding: String
    let qualifier: String?
    let changes: [AgentChangeRow]

    static let safetyNote = "Aim 只会修改以上普通计划，不会替你预约或作医疗决定。"

    var applyTitle: String {
        changes.isEmpty ? "确认执行" : "应用 \(changes.count) 项变更"
    }

    static func from(_ request: EveInputRequest) -> AgentChangePreview {
        AgentChangePreview(
            understanding: request.prompt ?? "要执行这项计划变更吗？",
            qualifier: request.qualifier,
            changes: (request.changes ?? []).map {
                AgentChangeRow(symbol: $0.symbol ?? "circle", field: $0.field, before: $0.before, after: $0.after)
            }
        )
    }
}
```

`safetyNote` 为客户端常量，不接受模型下发的内容。

- [ ] **Step 5: 实现 sheet**

创建 `apps/ios/AimApp/Features/Agent/AgentDiffSheet.swift`：

```swift
import SwiftUI

struct AgentDiffSheet: View {
    let preview: AgentChangePreview
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AimMetrics.space20) {
                VStack(alignment: .leading, spacing: AimMetrics.space4) {
                    Text("确认计划变更")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.aimTextPrimary)
                    Text("先确认 Aim 理解得对，再决定是否写入家庭计划。")
                        .font(.subheadline)
                        .foregroundStyle(Color.aimTextSecondary)
                }

                VStack(alignment: .leading, spacing: AimMetrics.space4) {
                    Text("我理解的是").aimLabelStyle()
                    Text(preview.understanding)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.aimTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let qualifier = preview.qualifier {
                        Text(qualifier)
                            .font(.subheadline)
                            .foregroundStyle(Color.aimTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !preview.changes.isEmpty {
                    VStack(alignment: .leading, spacing: AimMetrics.space8) {
                        Text("计划将这样变化").aimLabelStyle()
                        VStack(spacing: 0) {
                            ForEach(Array(preview.changes.enumerated()), id: \.element.id) { index, row in
                                changeRow(row)
                                if index < preview.changes.count - 1 {
                                    Divider().background(Color.aimSeparator)
                                }
                            }
                        }
                        .padding(.horizontal, AimMetrics.space12)
                        .background(Color.aimSurfaceSunken,
                                    in: RoundedRectangle(cornerRadius: AimMetrics.radiusDiffCard, style: .continuous))
                    }
                }

                HStack(alignment: .top, spacing: AimMetrics.space8) {
                    Image(systemName: "checkmark.shield")
                        .font(.footnote)
                        .foregroundStyle(Color.aimSuccess)
                    Text(AgentChangePreview.safetyNote)
                        .font(.footnote)
                        .foregroundStyle(Color.aimSuccess)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AimMetrics.space12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.aimSuccessSoft,
                            in: RoundedRectangle(cornerRadius: AimMetrics.radiusButton, style: .continuous))

                VStack(spacing: AimMetrics.space4) {
                    Button(action: onApply) {
                        Text(preview.applyTitle)
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AimMetrics.space12)
                            .background(Color.aimAccent,
                                        in: RoundedRectangle(cornerRadius: AimMetrics.radiusButton, style: .continuous))
                            .foregroundStyle(Color.aimTextOnAccent)
                    }
                    .buttonStyle(.plain)

                    Button("暂不修改", action: onDismiss)
                        .font(.body)
                        .foregroundStyle(Color.aimTextSecondary)
                        .padding(.vertical, AimMetrics.space8)
                }
            }
            .padding(AimMetrics.space20)
        }
        .background(Color.aimSurfaceRaised)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("agent-diff-sheet")
    }

    private func changeRow(_ row: AgentChangeRow) -> some View {
        HStack(alignment: .top, spacing: AimMetrics.space12) {
            Image(systemName: row.symbol)
                .font(.subheadline)
                .foregroundStyle(Color.aimAccent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.field)
                    .font(.subheadline)
                    .foregroundStyle(Color.aimTextPrimary)
                Text(row.valueText)
                    .font(.footnote)
                    .foregroundStyle(Color.aimTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AimMetrics.space12)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 6: 用 sheet 取代 ApprovalBar**

在 `AgentSheet.swift` 中：删除 `private struct ApprovalBar`；在 `statusView` 的 `.awaitingApproval` 分支返回 `EmptyView()`；在 body 上追加：

```swift
            .sheet(item: pendingApproval) { request in
                AgentDiffSheet(preview: AgentChangePreview.from(request)) {
                    store.approve(request, environment: session.environment)
                } onDismiss: {
                    store.cancelApproval(request, environment: session.environment)
                }
            }
```

并加辅助属性：

```swift
    private var pendingApproval: Binding<EveInputRequest?> {
        Binding(
            get: { if case let .awaitingApproval(request) = store.state { return request }; return nil },
            set: { if $0 == nil, case let .awaitingApproval(request) = store.state {
                store.cancelApproval(request, environment: session.environment)
            } }
        )
    }
```

- [ ] **Step 7: 运行测试**

Run: `make ios-test`
Expected: `AgentChangePreviewTests` 5 个测试 PASS，其余测试不回归

- [ ] **Step 8: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): confirm agent changes with field-level diff sheet"
```

---

### Task 9: Agent Tab 重构

恢复迁移 ExyteChat 时丢失的三个交互，并加「最近处理」台账。

**Files:**
- Modify: `apps/ios/AimApp/Features/Agent/AgentSheet.swift`
- Modify: `apps/ios/AimApp/Features/Agent/AgentStore.swift`

**Interfaces:**
- Consumes: `AgentStore.stop()`（已存在但无调用点）、`AimToastMessage`（Task 7）
- Produces: `AgentStore.activityLog: [AgentActivity]`、`struct AgentActivity { let id: UUID; let title: String; let occurredAt: Date; let canUndo: Bool }`

- [ ] **Step 1: 恢复快捷提问**

在 `AgentSheet` 的 `welcomeContent` 下方追加 chips。因 ExyteChat 无法预填输入框，chip 点击即**直接发送**：

```swift
    private let quickPrompts = ["这周还有什么要准备？", "帮我看看最近的记录", "我现在有点不舒服"]

    private var quickPromptRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AimMetrics.space8) {
                ForEach(quickPrompts, id: \.self) { prompt in
                    Button(prompt) {
                        store.draft = prompt
                        store.send(environment: session.environment)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.aimAccent)
                    .padding(.horizontal, AimMetrics.space12)
                    .padding(.vertical, AimMetrics.space8)
                    .background(Color.aimSurface, in: Capsule())
                    .overlay { Capsule().stroke(Color.aimAccent.opacity(0.2), lineWidth: 1) }
                    .accessibilityIdentifier("agent-quick-prompt")
                }
            }
            .padding(.horizontal, AimMetrics.space16)
        }
    }
```

在 `store.messages.isEmpty` 分支中渲染 `welcomeContent` 之后渲染 `quickPromptRow`。

- [ ] **Step 2: 恢复停止生成与错误重试**

把 `statusView` 的 `.streaming` 与 `.failed` 分支改为：

```swift
        case .streaming:
            HStack(spacing: AimMetrics.space8) {
                ProgressView().controlSize(.small)
                Text("正在整理回答…")
                    .font(.footnote)
                    .foregroundStyle(Color.aimTextSecondary)
                Spacer()
                Button("停止") { store.stop() }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.aimAccent)
                    .accessibilityIdentifier("agent-stop")
            }
            .padding(.horizontal, AimMetrics.space16)
            .padding(.vertical, AimMetrics.space8)
        case .failed(let message):
            HStack(alignment: .firstTextBaseline, spacing: AimMetrics.space8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.aimTextSecondary)
                Spacer()
                Button("重试") { store.retryLast(environment: session.environment) }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.aimAccent)
                    .accessibilityIdentifier("agent-retry")
            }
            .padding(.horizontal, AimMetrics.space16)
            .padding(.vertical, AimMetrics.space12)
            .background(Color.aimDangerSoft)
```

- [ ] **Step 3: 在 AgentStore 加 retryLast 与台账**

在 `AgentStore` 中追加：

```swift
    var activityLog: [AgentActivity] = []
    private var lastUserText: String?

    func retryLast(environment: APIEnvironment) {
        guard let lastUserText else { return }
        draft = lastUserText
        messages.removeAll { $0.text == lastUserText && $0.isUser }
        send(environment: environment)
    }
```

在 `send(environment:)` 中 `messages.append(...)` 之后记录 `lastUserText = text`。

在 `consume(_:)` 的 `.actionResult` 分支中追加台账：

```swift
        case .actionResult:
            state = .applied
            activityLog.insert(
                AgentActivity(id: UUID(), title: "已更新家庭计划", occurredAt: .now, canUndo: true),
                at: 0
            )
```

并在文件末尾定义：

```swift
struct AgentActivity: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let occurredAt: Date
    let canUndo: Bool
}
```

- [ ] **Step 4: 渲染台账**

在 `AgentSheet` 的 `ChatView` 之上、上下文卡之下，当 `!store.activityLog.isEmpty` 时渲染：

```swift
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Text("最近处理").aimLabelStyle()
            ForEach(store.activityLog.prefix(3)) { activity in
                HStack(spacing: AimMetrics.space8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.aimSuccess)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.title)
                            .font(.subheadline)
                            .foregroundStyle(Color.aimTextPrimary)
                        Text(activity.occurredAt, style: .time)
                            .font(.footnote)
                            .foregroundStyle(Color.aimTextSecondary)
                    }
                    Spacer()
                    if activity.canUndo {
                        Button("撤销") { store.undo(activity, environment: session.environment) }
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.aimAccent)
                    }
                }
            }
        }
        .padding(.horizontal, AimMetrics.space16)
        .padding(.vertical, AimMetrics.space8)
        .accessibilityIdentifier("agent-activity-log")
    }
```

在 `AgentStore` 中加：

```swift
    func undo(_ activity: AgentActivity, environment: APIEnvironment) {
        guard let sessionID else { return }
        activityLog.removeAll { $0.id == activity.id }
        let client = EveClient(environment: environment)
        state = .streaming
        activeTask = Task { [weak self] in
            do {
                let events = try await client.send(
                    sessionID: sessionID,
                    message: "撤销上一次计划变更",
                    from: self?.streamIndex ?? 0
                )
                for try await event in events { self?.consume(event) }
            } catch {
                self?.fail(error.localizedDescription)
            }
        }
    }
```

- [ ] **Step 5: 换主题为 token**

把 `chatTheme` 中的颜色全部换成新 token：`mainBG: .aimCanvas`、`mainTint: .aimAccent`、`mainText: .aimTextPrimary`、`mainCaptionText: .aimTextSecondary`、`messageMyBG: .aimAccent`、`messageMyText: .aimTextOnAccent`、`messageFriendBG: .aimSurface`、`messageFriendText: .aimTextPrimary`、`inputBG: .aimSurface`、`inputText: .aimTextPrimary`、`inputPlaceholderText: .aimTextSecondary`、`sendButtonBackground: .aimAccent`。

同时删除 `body` 上的 `.frame(maxWidth:maxHeight:)` 与 `.ignoresSafeArea()` —— 作为 Tab 内容它们会让导航栏顶到状态栏。

- [ ] **Step 6: 编译并测试**

Run: `make ios-build && make ios-test`
Expected: BUILD SUCCEEDED，测试 PASS

- [ ] **Step 7: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): restore agent stop, retry, quick prompts and activity log"
```

---

### Task 10: 修复记录分析入口

`RecordDetailView` 的「让 Agent 分析当前记录」当前完全失效。改为直接发起一轮对话。

**Files:**
- Modify: `apps/ios/AimApp/Features/Agent/AgentSheet.swift`
- Modify: `apps/ios/AimApp/Features/Agent/AgentStore.swift`
- Modify: `apps/ios/AimApp/Features/Records/RecordDetailView.swift:59-61`
- Modify: `apps/ios/AimApp/Tests/AgentStoreTests.swift`

**Interfaces:**
- Produces: `AgentSheet(autoSend:context:onClose:)`；`AgentStore.sendIfNeeded(_ text: String, environment:)`

- [ ] **Step 1: 写失败测试**

在 `apps/ios/AimApp/Tests/AgentStoreTests.swift` 追加：

```swift
@MainActor
final class AgentAutoSendTests: XCTestCase {
    func testAutoSendRecordsUserMessageOnce() {
        let store = AgentStore(context: nil)
        store.markAutoSent()
        XCTAssertTrue(store.hasAutoSent)
        store.markAutoSent()
        XCTAssertTrue(store.hasAutoSent)
    }

    func testFreshStoreHasNotAutoSent() {
        XCTAssertFalse(AgentStore(context: nil).hasAutoSent)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppTests/AgentAutoSendTests`

Expected: `value of type 'AgentStore' has no member 'markAutoSent'`

- [ ] **Step 3: 实现**

在 `AgentStore` 中追加：

```swift
    private(set) var hasAutoSent = false

    func markAutoSent() { hasAutoSent = true }

    func autoSend(_ text: String, environment: APIEnvironment) {
        guard !hasAutoSent else { return }
        markAutoSent()
        draft = text
        send(environment: environment)
    }
```

把 `AgentSheet` 的 init 改为：

```swift
    private let autoSend: String?

    init(autoSend: String? = nil, context: AgentContext? = nil, onClose: (() -> Void)? = nil) {
        _store = State(initialValue: AgentStore(context: context))
        self.autoSend = autoSend
        self.onClose = onClose
    }
```

删除原来的 `initialDraft` 参数与 `store.draft = initialDraft` 一行。在 body 上追加：

```swift
            .task {
                if let autoSend { store.autoSend(autoSend, environment: session.environment) }
            }
```

- [ ] **Step 4: 改调用点**

`RecordDetailView.swift:59-61` 改为：

```swift
        .fullScreenCover(isPresented: $showingAgent) {
            AgentSheet(
                autoSend: analysisPrompt(for: currentRecord),
                context: AgentContext(
                    title: "记录",
                    summary: "\(currentRecord.type.displayName)：\(currentRecord.displayTitle)"
                )
            )
        }
```

- [ ] **Step 5: 检查其它调用点**

Run: `grep -rn "AgentSheet(" apps/ios/AimApp --include="*.swift"`

确认没有残留的 `initialDraft:` 用法。

- [ ] **Step 6: 运行测试**

Run: `make ios-test`
Expected: PASS

- [ ] **Step 7: 提交**

```bash
git add apps/ios
git commit -m "fix(ios): send record analysis prompt instead of prefilling input"
```

---

### Task 11: 家庭页与残留失败态

**Files:**
- Modify: `apps/ios/AimApp/Features/Family/FamilyView.swift`
- Modify: `apps/ios/AimApp/Features/TaskDetail/TaskDetailView.swift:57-73`

- [ ] **Step 1: 修邀请 sheet 的静默失败**

把 `InviteMemberSheet` 的 body 改为：

```swift
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("邀请谁加入") {
                    TextField("手机号", text: $phone)
#if os(iOS)
                        .keyboardType(.phonePad)
#endif
                    Picker("账号身份", selection: $role) {
                        ForEach(FamilyRole.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.aimDanger) }
                }
            }
            .navigationTitle("邀请成员")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("发送") { Task { await submit() } }
                            .disabled(phone.filter(\.isNumber).count < 6)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        if await store.invite(phone: phone, role: role) {
            dismiss()
        } else {
            errorMessage = store.errorMessage ?? "邀请没有发出去，稍后再试。"
        }
    }
```

- [ ] **Step 2: 修延期 sheet 的失败不可见**

把 `TaskDetailView` 的延期 sheet 改为：

```swift
        .sheet(isPresented: $showingDelay) {
            NavigationStack {
                Form {
                    DatePicker("新的截止日期", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    if let delayError {
                        Text(delayError).foregroundStyle(Color.aimDanger)
                    }
                }
                .navigationTitle("延期事项")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingDelay = false }.disabled(store.isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if store.isSaving {
                            ProgressView()
                        } else {
                            Button("保存") {
                                Task {
                                    delayError = nil
                                    if await store.delay(until: dueDate) {
                                        showingDelay = false
                                    } else {
                                        delayError = store.errorMessage ?? "没能保存新的日期，稍后再试。"
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
```

并加 `@State private var delayError: String?`。

- [ ] **Step 3: 家庭成员行加待办计数**

在 `familyMemberRow` 的副标题中，把 `member.status == "active" ? "已加入" : "等待确认"` 改为拼接待办数：

```swift
                Text(statusText(member))
```

```swift
    private func statusText(_ member: FamilyMember) -> String {
        let base = member.status == "active" ? "已加入" : "等待确认"
        guard let count = store.openTaskCount(for: member.accountID), count > 0 else { return base }
        return "\(base) · \(count) 项待办"
    }
```

在 `FamilyStore` 中加：

```swift
    var openTaskCounts: [UUID: Int] = [:]

    func openTaskCount(for accountID: UUID) -> Int? { openTaskCounts[accountID] }
```

在 `TimelineStore.load()` 成功后把计数写入 —— 或更简单地在 `FamilyStore.load()` 中一并拉取 `loadPlan()` 并按 `assignedMemberID` 聚合。选后者，避免跨 store 依赖：

```swift
        if let plan = try? await repository?.loadPlan() {
            openTaskCounts = Dictionary(
                grouping: plan.tasks.filter(\.isOpen).compactMap(\.assignedMemberID),
                by: { $0 }
            ).mapValues(\.count)
        }
```

- [ ] **Step 4: 视觉换 token**

把 `FamilyView` 中所有 `Color.secondary`、`.foregroundStyle(.secondary)` 换为 `Color.aimTextSecondary`，背景换为 `Color.aimCanvas`，并给 `List` 加 `.scrollContentBackground(.hidden)`。

- [ ] **Step 5: 编译验证**

Run: `make ios-build && make ios-test`
Expected: BUILD SUCCEEDED，测试 PASS

- [ ] **Step 6: 提交**

```bash
git add apps/ios
git commit -m "fix(ios): surface invite and delay failures in their own sheets"
```

---

### Task 12: 时间线的头部、折叠、滑动与回到今天

补齐规格 §4.3、§4.4、§5.6、§8.1 四项在 Task 6 中未实现的行为。

**Files:**
- Modify: `apps/ios/AimApp/Features/Timeline/TimelineView.swift`
- Modify: `apps/ios/AimApp/Features/Timeline/TimelineStore.swift`
- Create: `apps/ios/AimApp/Features/Timeline/TimelineHeader.swift`

**Interfaces:**
- Consumes: `TimelineStore.weeks`、`TimelineStore.currentWeek`
- Produces: `TimelineHeader(week:days:date:onFilter:onCompose:onAgent:)`、`TimelineStore.isCollapsed(_:)`、`TimelineStore.expand(_:)`

- [ ] **Step 1: 自定义头部**

创建 `apps/ios/AimApp/Features/Timeline/TimelineHeader.swift`：

```swift
import SwiftUI

struct TimelineHeader: View {
    let week: Int?
    let days: Int
    let date: Date
    @Binding var filter: TimelineFilter
    let onCompose: () -> Void
    let onAgent: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: AimMetrics.space4) {
                Text(dateText)
                    .font(.caption2)
                    .tracking(0.9)
                    .foregroundStyle(Color.aimAccent)
                Text(titleText)
                    .font(.largeTitle.weight(.medium))
                    .foregroundStyle(Color.aimTextPrimary)
            }
            Spacer(minLength: AimMetrics.space8)
            HStack(spacing: AimMetrics.space8) {
                Menu {
                    Picker("筛选", selection: $filter) {
                        ForEach(TimelineFilter.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                } label: {
                    circle("line.3.horizontal.decrease", tinted: filter != .all)
                }
                .accessibilityLabel("筛选")
                .accessibilityIdentifier("timeline-filter")

                Button(action: onCompose) { circle("plus", tinted: false) }
                    .accessibilityLabel("新增记录")

                Button(action: onAgent) { circle("wand.and.sparkles", tinted: true) }
                    .accessibilityLabel("问一问")
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

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.calendar = PregnancyDateCalculator.calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }
}
```

在 `TimelineStore` 中暴露 `var currentDays: Int` 与 `var asOf: Date`：`load()` 中记录 `asOf = todaySnapshot.asOf`、`currentDays = todaySnapshot.days`。

在 `TimelineView` 中把 `.navigationTitle` / `.toolbar` 整段删除，改为在 `timeline` 的 `List` 之上放 `TimelineHeader`，并给 `NavigationStack` 加 `.toolbar(.hidden, for: .navigationBar)`。

- [ ] **Step 2: 未来周折叠**

在 `TimelineStore` 中追加：

```swift
    var expandedFarWeeks: Set<Int> = []

    func isCollapsed(_ week: TimelineWeek) -> Bool {
        guard let current = currentWeek else { return false }
        guard week.position == .future, week.week > current + 4 else { return false }
        return !expandedFarWeeks.contains(week.week)
    }

    func expand(_ week: TimelineWeek) {
        expandedFarWeeks.insert(week.week)
    }
```

在 `TimelineView.rows(for:)` 开头插入：

```swift
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
```

并在该 `else` 分支内保留原有的焦点卡与 `ForEach`，在函数末尾补 `}`。折叠时该周的 Section header 仍然渲染。

- [ ] **Step 3: 滑动完成与延期**

在 `TimelineView.row(_:)` 的 `.task` 分支上追加：

```swift
            .swipeActions(edge: .leading) {
                if task.isOpen {
                    Button {
                        Task {
                            await store.complete(task)
                            completedTaskID = task.id
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
```

在 `TimelineView` 中加 `@State private var delayTarget: TaskItem?`、`@State private var completedTaskID: UUID?`，并加：

```swift
            .sheet(item: $delayTarget) { task in
                TaskDelaySheet(task: task, repository: planStore.repository) {
                    delayTarget = nil
                    Task { await store.load() }
                }
            }
```

`TaskDelaySheet` 复用 Task 11 Step 2 中已改好的延期表单 —— 把该表单从 `TaskDetailView` 中抽为独立的 `struct TaskDelaySheet: View`，放在 `Features/TaskDetail/TaskDetailView.swift` 内，`TaskDetailView` 与时间线共用它。

在 `TimelineStore` 中加：

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

- [ ] **Step 4: 回到今天的触发条件**

iOS 17 没有 `onScrollGeometryChange`，用 PreferenceKey 上报今天锚点的位置。

在 `TimelineView.swift` 末尾加：

```swift
private struct TodayOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
```

给今天那一组的 Section header 追加：

```swift
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: TodayOffsetKey.self,
                                        value: proxy.frame(in: .named("timeline")).minY
                                    )
                                }
                            }
```

给 `List` 加 `.coordinateSpace(name: "timeline")` 与：

```swift
            .onPreferenceChange(TodayOffsetKey.self) { offset in
                let threshold = UIScreen.main.bounds.height * 2
                showsBackToToday = abs(offset) > threshold
            }
```

- [ ] **Step 5: 编译并测试**

Run: `make ios-build && make ios-test`
Expected: BUILD SUCCEEDED，测试 PASS

手动验证：滚动到远离今天两屏后「回到今天」浮出，点击回到锚点；孕周超过当前 +4 的分组显示为一行摘要，点击展开；任务行左右滑分别出现完成与延期。

- [ ] **Step 6: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): add timeline header, week folding and swipe actions"
```

---

### Task 13: 触觉反馈、深色模式与无障碍验收

**Files:**
- Modify: `apps/ios/AimApp/Features/Timeline/TimelineView.swift`
- Modify: `apps/ios/AimApp/Features/Agent/AgentDiffSheet.swift`
- Modify: `apps/ios/AimApp/Features/Records/RecordComposerView.swift`
- Modify: `apps/ios/AimApp/UITests/CoreJourneyUITests.swift`

- [ ] **Step 1: 加触觉反馈**

`completedTaskID` 已在 Task 12 Step 3 加入 `TimelineView` 并在滑动完成时设置。此处只需在 `List` 上追加：

```swift
            .sensoryFeedback(.success, trigger: completedTaskID)
```

在 `AgentDiffSheet` 的 `onApply` 外层包一个 `@State private var applied = 0`，`onApply` 内 `applied += 1`，并加 `.sensoryFeedback(.success, trigger: applied)`。

在 `RecordComposerView` 的 `save()` 成功分支加同样模式。

- [ ] **Step 2: 深色模式人工验收**

在 Xcode Canvas 或模拟器中，对以下界面各截一次浅色与深色：时间线、Agent 对话、diff sheet、toast、家庭页、记录 composer、任务详情。

逐项确认：无白底白字；卡片与页面底色可区分；陶土色在深色底上可读；toast 与页面形成反差。

发现问题时只调整 colorset 的 Dark 分量，不改 Light。

- [ ] **Step 3: Dynamic Type 验收**

模拟器 Settings → Accessibility → Display & Text Size → Larger Text 拉到最大（AX5），逐屏确认无文字截断。

对被截断的行，给对应 `Text` 加 `.fixedSize(horizontal: false, vertical: true)`；若整行仍放不下，把 `HStack` 换成 `ViewThatFits { HStack { … } ; VStack(alignment: .leading) { … } }`。

- [ ] **Step 4: VoiceOver 验收**

打开 VoiceOver，在时间线上左右滑动遍历。确认：导轨与孕周头不被单独朗读为无意义元素；每个任务行朗读为「未完成，晚饭后散步 20 分钟，妈妈，19:30」这样的一句。

不符合时给容器加 `.accessibilityElement(children: .combine)`，给装饰元素加 `.accessibilityHidden(true)`。

- [ ] **Step 5: 更新 UI 测试**

把 `CoreJourneyUITests` 中的 Tab 名从「今天」改为「孕期」，删除对「记录」Tab 的点击，改为点击时间线工具栏的「新增记录」。为时间线新增一个测试：

```swift
    func testTimelineAnchorsOnTodayAndOffersAgent() throws {
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

        XCTAssertTrue(app.otherElements["timeline-today-anchor"].waitForExistence(timeout: 8))

        app.buttons["global-agent-button"].tap()
        XCTAssertTrue(app.navigationBars["问一问"].waitForExistence(timeout: 3))
    }
```

- [ ] **Step 6: 跑全量验证**

Run: `make ios-build && make ios-test`
Expected: BUILD SUCCEEDED，全部单元测试与 UI 测试 PASS

- [ ] **Step 7: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): add haptics and verify dark mode and accessibility"
```

---

## 验收对照

实施完成后，逐条核对规格 §12：

1. 启动直接定位今天 — Task 6 Step 2（`proxy.scrollTo` 在 `.task` 中无动画执行）
2. 三段导轨可区分、孕周头吸顶 — Task 4 Step 1、Task 6 Step 2（`.listStyle(.plain)` 的 Section header 默认吸顶）
3. 暖色底在有无数据两态一致 — Task 6 Step 2（`.scrollContentBackground(.hidden)`）
4. 深色模式全部可读 — Task 3 Step 1、Task 13 Step 2
5. 三档权限三种 UI — Task 8（确认）、Task 7（toast）、Task 4 Step 3（来源标记）
6. 变更带来源标记且可撤销 — Task 1、Task 4 Step 3、Task 9 Step 4
7. 记录分析入口进入即有对话 — Task 10
8. sheet 内失败可见、按钮 loading — Task 11
9. 网络失败显示错误态与重试 — Task 6 Step 3
10. AX5 无截断、VoiceOver 顺序正确 — Task 13 Step 3、Step 4

规格中另外四项行为的落点：

- §4.3 未来周折叠 — Task 12 Step 2
- §4.4 回到今天的触发 — Task 12 Step 4
- §5.6 头部（日期小字 + 孕周大标题 + 三个圆按钮） — Task 12 Step 1
- §8.1 滑动完成与延期 — Task 12 Step 3
