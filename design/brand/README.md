# Aim Logo

## 当前正式版本

正式 Logo 使用用户确认的第一张原始生成稿。外侧拱形代表家庭共同形成的守护边界，内部向上的连续曲线代表孕期与家庭成长路径，鼠尾草绿圆点代表当前阶段最值得关注的下一步。

当前版本不再使用后来重绘的字母 `A` 方案。

## 文件

- `aim-logo-selected.png`：用户确认的第一张原始透明 PNG，是正式 Logo 的唯一图形来源。
- `aim-app-icon.png`：在原图下铺 `#FFF8F1` 暖米白背景并缩放生成的 1024 × 1024 App Icon 母版；没有重绘轮廓。
- `explorations/letter-a/`：已拒绝的字母 `A` 重绘方案，仅保留追溯，不得用于产品。

正式 iOS 图标位于 `apps/ios/AimApp/Resources/Assets.xcassets/AppIcon.appiconset/`。Asset Catalog 使用无 Alpha 的 1024 × 1024 PNG，Debug 与 Release 构建均指定 `AppIcon`。

## 使用约束

- 不得把正式 Logo 再次重绘为字母 `A` 或其他轮廓。
- App Icon 只允许增加系统要求的实色背景、尺寸缩放和无 Alpha 编码。
- 不单独改变绿色圆点、内部曲线或外侧拱形的位置与比例。
