# 2026-10-12 TestFlight 上传记录

开发源码已提交 `eb1cbfc89d483c70c4daa18e95b07bd2abf7f58a`，快进合并到本地 `development`。本轮覆盖完整主线功能与本地验收，范围详见 [产后验收记录](2026-10-12-postpartum-validation.md)。

## 发行结果

- 版本：**1.0.0（202610121442）**，Bundle ID `com.aim.pregnancy`。
- 已从该提交重新归档并使用 Xcode 自动发行签名导出。签名验证通过，团队 `X4TB4579NS`；`get-task-allow=false`，`beta-reports-active=true`；profile 到期 2027-09-21。
- EPDS 和产后清单资源均在发行包内；分娩、情绪、产后以及此前本地提醒代码包含在此版本。
- Xcode 上传返回 **Upload succeeded / EXPORT SUCCEEDED**。结束时 Apple 状态为 **Uploaded package is processing**；尚未另外确认 TestFlight 可安装或测试员安装状态。
- 保持原有 ATS 配置，未把尚未配置 HTTPS 的生产端点改为强制 HTTPS。

## 可复核产物

- 最终归档：`/tmp/AimApp-202610121442-final.xcarchive`。
- 归档与发行导出日志：`/tmp/aim-testflight-202610121442-final-archive.log`、`/tmp/aim-testflight-202610121442-final-export.log`。
- 已验证的发行 IPA：`/tmp/aim-testflight-202610121442-final-export/AimApp.ipa`；SHA-256 记录在 `/tmp/aim-testflight-202610121442-receipt.json`。
- 上传日志：`/tmp/aim-testflight-202610121442-upload.log`；2026-10-12 14:59:59（北京时间）返回成功与 processing。
- 当前本地回执：`/tmp/aim-testflight-current.json`。回执中的源码提交是 app 构建来源；后续仅文档提交不改变 app 来源。

## 收尾与后续发布

> 后续更新：用户已确认全部在用手机更新，生产部署与 GitHub 同步已完成，详见 [生产发布记录](2026-10-12-production-release.md)。以下保留上传结束时的状态。

- 工作已合并本地 development；没有推送 GitHub，沿用路线图中远端推送需明确授权的约定。
- 本地 API/Eve 均健康，数据库 0013 head；Eve 已恢复真实 deepseek-flash 模式。
- 生产后端与数据库没有部署或迁移。必须先确认在用手机更新到兼容 iOS 版本，随后备份数据库、迁移到 0013、部署 API/Eve/网页并做生产验收。旧版 same_day 判断差异仍是必须满足该次序的原因。
- 专业医学复核清单仍在 `content/README.md`；历史偶发孕期保存 500 本轮未复现，继续保留事实边界。真机拍照和复杂图片质量不包含在单张合成图验收里。
