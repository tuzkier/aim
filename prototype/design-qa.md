# Design QA

## Comparison Target

- 视觉方向：`reference/today-selected-concept.png`
- 交互复测证据：`audit/interaction-v2/`
- 设备：iPhone，393 × 852 CSS px，浅色外观
- 原则：温馨但克制、无插画、Apple 原生层级、行动优先而非对话优先

## Visual Result

更新后的 Today、任务详情、Agent 确认、四周计划和家庭页继续使用统一的暖米色背景、克制的陶土色操作色、原生大标题、分组列表和 BottomSheet。新增交互没有引入插画、渐变或聊天气泡，也没有破坏已确认的 iOS 方向。

## Interaction Result

- 任务具备 `待处理 / 已安排 / 已完成` 生命周期，完成预约后动态推进下一优先事项。
- 时间、负责人和来源可见，任务可延期、重新分配和撤销。
- Agent 采用 `理解 → 预览 → 确认 → 应用 → 撤销`，确认前不修改计划。
- Agent 不虚构预约时刻，并明确普通计划与医疗决定的边界。
- Agent 修改后，Today、四周计划和家庭分工读取同一份状态并显示来源。
- 家庭邀请成功后新增“等待加入”成员，结果页有明确退出动作。
- 键盘在提交、关闭和切换页面后完全退出，不再遮挡 Tab 或造成错误滚动位置。

## Evidence

- `audit/interaction-v2/01-agent-review.png`
- `audit/interaction-v2/02-plan-synced.png`
- `audit/interaction-v2/03-task-actions.png`
- `audit/interaction-v2/04-today-dynamic.png`
- `audit/interaction-v2/05-family-synced.png`
- `audit/interaction-v2/audit.md`

## Remaining Implementation QA

正式 SwiftUI 版本仍需验证 Dynamic Type、VoiceOver 顺序、减少动态效果、系统键盘和网络失败态；原型阶段没有以截图替代这些原生验收。

final result: passed
