# 产后延续接续现场（未完成验收）

> 本文件保留中断时的历史现场。后续已完成开发与验证，最终结论见 [产后延续验收记录](2026-10-12-postpartum-validation.md)。下文不是当前进度。

2026-10-12，中断后的实际现场。分支 `dev/postpartum-continuity`，HEAD `9d7c44e`；产后源码仍是未提交改动，不可当作已完成或可发布。

## 已完成并合并本地 development

- `f24d759`：分娩关联修复；515 个单元测试、原主旅程与旧断点两个入口 UI 通过。
- `cb7d8fb`：每日心情与 EPDS；孕期和通用记录 UI 通过，产后节点真实数据验证仍待本项完成。

## 产后改动当前状态

- 已写生命周期字段、宝宝表与 `0013_postpartum_babies` 迁移；出生/修正/撤回事务、任务不适用状态与恢复轨迹、北京时间业务日期。
- 已写宝宝档案、三类照护、引用权限与时间校验、睡眠派生时长；原生页面、首页阶段、真实生日传入情绪节点、停止产后胎动计划、AIM 读取与专用日志工具。
- 2026 年国家免疫程序核对清单与证件安排资源已写入。
- 当前证据：API 552 passed；Agent 新增工具测试纳入 test 命令后 62 passed / 3 skipped；iOS 全量 536 passed。之后新增的两个 PostpartumStore 回归尚未运行。

## 必须继续的验证

- `testPostpartumBirthBabyCareAndSixWeekAssessmentJourney` 未通过完整旅程。第一轮是 Toggle 行中心点击未开启，改为开关坐标后已越过；随后照护已实际保存，但 List 虚拟化让测试找不到屏幕外的统计/按钮，已补上下滚动和保存关闭等待。
- 第 5 次 `/tmp/aim-postpartum-ui5.log` 在开关点击附近因本次中断停止，未产出通过结论。目前没有仍运行的 xcodebuild；下一次使用新的 resultBundlePath 重跑。
- 必须跑到三类记录、首页产后、真实日期修正及 14/42 天自评提示；再加原生撤回、编辑/删除、宝宝档案修正与多宝宝覆盖。
- 日期修正轮盘为中文 wheel，需要按实际 wheel 值调整测试，不弱化日期断言。
- 跑新 store 回归、完整 API/Agent/iOS 回归、迁移升级与 Release 签名导出；做最终源码审查，尤其生命周期与日志并发、计划取消恢复、隐私与日期边界。
- 还有两个旧 AIM UI 用例未按 WebView 重写；照片识别完整 UI 范围仍未覆盖。

## 运行证据与发布

`/tmp/aim-postpartum-verify4.log`、`/tmp/aim-postpartum-agent-newtests.log`、`/tmp/aim-postpartum-units-all1.xcresult`、`/tmp/aim-postpartum-ui1.log` 至 `ui5.log`。

`ui3` 导出的最后一帧显示喂养 60.5 毫升记录已保存，测试失败不是 API 保存失败；截图 `/tmp/aim-postpartum-ui3-last.png`。首轮出生开关失败截图 `/tmp/aim-postpartum-ui1-last.png`。

本地 API/Eve 已重建并迁移；未部署生产、未推送、未上传包含新增功能的新包。现有 TestFlight `202610111650` 仅对应 `56be775`，不含本次分娩修复、情绪或产后改动。最后统一发布时仍须先让使用设备更新再部署后端。
