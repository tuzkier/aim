# Aim iOS

原生 SwiftUI 客户端骨架，部署目标为 iOS 17。当前纵切已经包含：

- 家庭账号、家庭、孕期作用域的本地会话保存；
- 会话 Token 写入 Keychain，家庭/孕期 scope 仅保存非敏感 ID；
- Today / Plan / Family 三个主入口；
- 任务详情、完成、延期和家庭成员邀请交互；
- Agent Sheet、Eve 原生 NDJSON 解码、断线 cursor 和审批响应；
- SwiftData 的 Today 缓存、Eve cursor 与普通待办离线操作模型；
- 由 `contracts/public-api/openapi.json` 对齐的 DTO 边界。

## 本地运行与验证

工程需要 Xcode 26.6 或更高版本、iOS 17 以上 SDK。若 Xcode 尚未设为当前开发者目录，可先设置：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

在 Xcode 中打开 `AimApp.xcodeproj`，选择 `AimApp` scheme 和任一 iOS Simulator；或直接运行：

```bash
make ios-build
make ios-test
```

本地 Docker 环境启动后，App 首屏只使用手机号进入演示账号；进入后可以选择录入预产期或末次月经，Aim 会按 280 天互相换算，不会发送短信，也不会要求用户填写内部 ID 或 Token。演示账号接口只在 Compose 的 `DEV_AUTH_ENABLED=true` 下开启，正式短信登录接入后替换该适配器即可。当前工程已通过 iOS Simulator 编译，并在 iPhone 17 Pro（iOS 26.5）上通过 XCTest；后端和 Eve Runtime 的真实集成验收仍按仓库根目录的验证命令执行。
