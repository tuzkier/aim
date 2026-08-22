# 孕期日期录入：去掉默认预填、首次进入强制填写

日期：2026-08-21

## 问题

`PregnancySetupView` 的日期选择器预填「今天 + 154 天」（`TodayView.swift:7`）。
280 − 154 = 126 天，正好是孕 18 周 0 天，而 `content/pregnancy-tasks/` 里唯一
有完整内容的就是 `week-18.yaml`。于是「不碰日期直接保存」会得到一份看起来
很完整的计划，掩盖了两件事：

1. 用户可能没看清就提交了一个**假预产期**。这是医疗相关数据。
2. 内容库其实只覆盖 5–12 周和 18–19 周，其余孕周计划为空。默认值刚好避开了这个事实。

同时，孕期信息一旦创建就**再也无法修改**——`PregnancySetupView` 只在没有档案时可达，
后端也只有创建接口（`POST /api/v1/families/{family_id}/pregnancies`），没有更新接口。

## 范围

本次只做 A、B 两项（纯前端）。C（设置里修改预产期）涉及后端新增接口与任务迁移策略，
单独一轮，见文末「后续」。

## A. 去掉默认预填

`PregnancySetupView` 的 `selectedDate` 从 `Date`（预填 154 天后）改为 `Date?`（初值 `nil`）。

- 未选择时：不渲染 `DatePicker`，只显示「预产期 / 末次月经」分段控件 + 一个「选择日期」按钮；
  「保存并生成计划」禁用。
- 已选择时：展开 `DatePicker`，保存按钮可用。
- 切换「预产期 / 末次月经」时，已选日期按 280 天换算保留（沿用现有 `PregnancyDateMode` 逻辑），
  未选择则保持未选择。

iOS 的 `DatePicker` 必须绑定一个非可选 `Date`，因此内部用
`Binding<Date>(get: { selectedDate ?? fallback }, set: { selectedDate = $0 })`，
`fallback` 仅用于控件初次展开时的落点，不参与提交。

## B. 首次进入强制填写

登录后 `session.pregnancyID == nil` 时，直接呈现 `PregnancySetupView`，且不可下滑关闭
（`.interactiveDismissDisabled()`），填完才进时间线。

替换掉现在的做法：时间线显示 `AimEmptyState`（「先补充孕期信息」+ 按钮），用户可以
停在空时间线上不填。改为准入门槛后，`setupPrompt` 这段空状态不再需要。

## 数据流

不变。前端仍然调用现有的
`POST /api/v1/families/{family_id}/pregnancies`，请求体不变；后端按预产期倒推
280 天得出孕龄，再用 `initial_plan_items(gestational_week)` 从 `content/` 生成计划。
本次改动不触碰后端和 `content/`。

## 测试

- 单元：未选择日期时保存按钮禁用；选择后可用；切换日期模式时已选值按 280 天换算。
- UI：全新账号登录后，孕期设置界面**自动出现**且不可绕过；不选日期时无法保存；
  选定日期后进入时间线并看到对应孕周的计划。
- 现有 UI 测试中「点补充孕期信息 → 点保存并生成计划」的两处需要改为显式选择日期，
  否则会因保存按钮禁用而失败。这正是本次改动要防住的行为。

## 后续（C，单独一轮）

设置里修改预产期。需要：

- 后端新增 `PATCH /api/v1/pregnancies/{pregnancy_id}`，接受预产期或末次月经。
- 修改后的任务迁移策略（已确认）：保留用户手动新建的、已完成的、以及
  `changed_by_actor = agent` 的任务；只删除并重建 `source_type = template` 且
  `status = todo` 的任务。
- 前端在家庭 Tab 增加「孕期信息」一栏，复用 `PregnancySetupView` 的编辑模式。
  编辑模式下**应当**预填当前预产期——那是展示已有数据，不是本文档反对的凭空默认值。
