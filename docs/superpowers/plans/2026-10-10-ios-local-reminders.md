# iOS 本地提醒实施计划

> 使用 executing-plans 技能按任务完成和验证。

**Goal:** 路线图第 6 项全部接通，真实系统通知与点击跳转可用。

**当前结果（2026-10-10）：** 已完成；455 个单元测试、真实通知冷启动与撤销、记忆及产检回归通过，详见 `../reports/2026-10-10-ios-local-reminders-validation.md`。

**Architecture:** 纯规划器 + UserNotifications 协议适配器 + 有作用域保护的协调器 + 设置/简报界面，复用业务仓储和既有胎动/待办页面。

**Tech Stack:** SwiftUI、UserNotifications、XCTest/XCUITest，现有本地 API 栈。

## Task 1：模型与规划器

- [x] 在 `Features/Reminders/ReminderModels.swift` 实现 scope、路由、偏好、通知候选及规划器。
- [x] 测试未来时间、胎动 28/42 周边界、今日计数抑制、自己/他人分工、已完成/无日期、改期日期、免打扰跨日与同日、容量排序、非法路由。

## Task 2：系统适配与生命周期

- [x] `Core/Notifications/ReminderCenter.swift` 定义可测试协议及 UNUserNotificationCenter 适配器，启动时注册 delegate。
- [x] 协调器实现授权、偏好持久化、最新数据读取、重排、代次保护、旧 scope 撤销、冷启动待处理路由。
- [x] 测试拒绝权限、相同 id 替换、任务完成/改期后取消、跨 scope/登出与异步添加中的清理。

## Task 3：设置、简报、业务更新与跳转

- [x] `Features/Reminders/ReminderSettingsView.swift` 实现设置、系统状态、测试提醒、本周简报。
- [x] `ProfileView.swift` 加入口；`AimApp.swift` 注入协调器、前台重排、响应路由；`AppSessionStore.swift` 作用域变化广播。
- [x] 业务待办写入成功与胎动计数状态变化触发更新。通知点击不改业务数据，校验 scope 后取最新详情。
- [x] 登记工程，全部单元测试、既有记忆/报告回归、设置 UI 通过。

## Task 4：真实通知与收尾

- [x] 申请实际系统权限，检查实际 pending 请求；发送 10 秒测试提醒，切到后台，确认系统显示并点击进入简报。
- [x] 验证关闭开关/退出登录清理；冷启动点击处理；记录模拟器/系统的验证边界。
- [x] `make verify`、iOS 测试和截图复核；更新路线图与验收记录，提交并合并本地 development。
