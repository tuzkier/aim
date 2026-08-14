# Aim iOS

原生 SwiftUI 客户端骨架，部署目标为 iOS 17。当前纵切已经包含：

- 家庭账号、家庭、孕期作用域的本地会话保存；
- 会话 Token 写入 Keychain，家庭/孕期 scope 仅保存非敏感 ID；
- Today / Plan / Family 三个主入口；
- 任务详情、完成、延期和家庭成员邀请交互；
- Agent Sheet、Eve 原生 NDJSON 解码、断线 cursor 和审批响应；
- SwiftData 的 Today 缓存、Eve cursor 与普通待办离线操作模型；
- 由 `contracts/public-api/openapi.json` 对齐的 DTO 边界。

当前环境只有 Command Line Tools，没有完整 Xcode 或 iOS Simulator，因此本轮不能声称已完成 Simulator 编译验收。安装 Xcode 后打开 `AimApp.xcodeproj`，运行 `AimApp` scheme，并先配置有效的会话 Token 和三个 scope ID。
