# 分娩记录关联修复 Implementation Plan

> **For agentic workers:** 使用 executing-plans 顺序实施；本次用户已授权持续实施与验证。

**Goal:** 计时页与分娩页的出发记录关联准确，旧计时不被自动关联，前台补存与出发保存并发不会丢失已成功保存的记录编号。

**Architecture:** 保留 records 契约与五秒等待上限。`HospitalTripLink` 增加旧计时决策，两个页面共用；`ContractionStore` 按作用域共享一个保存 Task，记录本地结果编号到服务端记录编号，调用方加入已有 Task 而不是直接返回 nil。切换作用域后旧 Task 只清理旧队列，不能返回旧记录关联或更新新作用域状态。

**Tech Stack:** SwiftUI、Observation、XCTest、XCUITest。

## 设计决定

- 直接忽略旧计时会让本地断点无处处理；自动保存并关联会把历史当作当前。因此出发时提供保存旧计时、丢弃旧计时、先出发稍后处理三条路径，均不自动关联超过六小时的计时，且仍可取消。
- 保存旧计时仅等待五秒，失败或超时继续保留本地队列，不阻止记录出发。
- 快速保存时不得因取消超时 Task 而误报超时；超时 Task 睡眠结束后检查取消状态。
- 按账号与孕期隔离保存 Task 与返回编号。已有保存请求不重复创建；新队列条目由同一循环继续处理。

## Task 1：回归测试

**Files:** `apps/ios/AimApp/Tests/ContractionModelsTests.swift`、`apps/ios/AimApp/Tests/ContractionStoreTests.swift`。

1. 增加六小时边界与旧计时优先决策的测试，未来历史不关联。
2. 先制造失败保存，再挂起补存，同时结束新的计时；放行后应关联第二条记录且每条只创建一次。
3. 保存过程中换账号或孕期，旧调用不得返回可关联的旧编号，新队列可正常保存。
4. 将挂起假仓库放在 MainActor，避免测试自身竞态。
5. 先跑新回归，确认旧实现不满足约束。

## Task 2：保存队列与关联决策

**Files:** `Features/Labor/ContractionModels.swift`、`Features/Labor/ContractionStore.swift`（均位于 `apps/ios/AimApp/`）。

1. 增加 `.resolveStale`，在 `.finishActive` 前检查 `active.isStale(at:)`；已保存历史限定结束时间距现在为 0–7200 秒。
2. 保存加入现有 Task：`let task = savingTask ?? startSaving(); await task.value`，再从当前作用域的 `[result.id: record.id]` 返回目标编号。
3. 每次绑定变化增加 generation；旧 Task 不更改新作用域的 `isSaving`、错误与编号映射。
4. 超时取消检查；保持超时后后台补存与落盘清理。
5. 运行两类单元测试，确认边界、并发、超时和作用域隔离。

## Task 3：统一两个出发入口

**Files:** `Features/Labor/LaborView.swift`、`Features/Labor/ContractionTimerView.swift`。

1. 两个页面统一使用 `HospitalTripLink.decide`，没有进行中计时也可关联两小时内的最新历史。
2. 共享旧计时确认内容，保存旧计时后不附加其编号；丢弃清本地断点；稍后处理保留断点。
3. 保存期间禁用计时编辑，防止队列截取过程中继续改同一次计时。
4. 跑全部 iOS 单元测试与计时→保存→出发→首页横幅→撤回 UI 旅程；增加旧计时出发选择的 UI 回归。
5. 更新路线图和验证报告，提交修复，再进入情绪关照设计与实施。

## 验证命令

```sh
cd apps/ios
xcodebuild test -project AimApp.xcodeproj -scheme AimApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:AimAppTests/ContractionModelsTests -only-testing:AimAppTests/ContractionStoreTests CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

最终使用 `-only-testing:AimAppTests` 验证所有单元测试，使用 `-only-testing:AimAppUITests/CoreJourneyUITests/testLaborModeTimesContractionsAndAnnouncesTheHospitalTrip` 验证 UI，并按新增旧计时用例单独运行。生产、远端推送与新 TestFlight 上传留到最后统一处理。
