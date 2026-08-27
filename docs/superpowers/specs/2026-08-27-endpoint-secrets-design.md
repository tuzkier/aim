# 部署地址移出版本库

2026-08-27

## 问题

`tuzkier/aim` 是公开仓库。部署机的公网 IP 硬编码在 iOS 源码、Info.plist 注释、
三份 README 和一份计划文档里，共 175 处出现，横跨全部 101 个提交。

这台机器当前是明文 HTTP + 开放注册，地址公开等于把入口摆在外面。

## 设计

分两层，缺一不可：**构建期注入管住将来，历史改写管住过去**。只做后者的话，下一次
部署又会把地址写回代码。

### 构建期注入

```
apps/ios/AimApp/Config/
├── Endpoints.xcconfig                  跟踪。默认空值 + #include? 本地文件
├── Endpoints.local.xcconfig.example    跟踪。模板与写法说明
└── Endpoints.local.xcconfig            .gitignore 排除。真实地址
```

`Endpoints.xcconfig` 挂在 App target 的 Debug/Release `baseConfigurationReference` 上：

```
AIM_REMOTE_BASE_URL =
#include? "Endpoints.local.xcconfig"
```

`#include?` 是可选包含，文件缺失时静默跳过、零警告；放在默认赋值之后，本地值才能
覆盖它。地址经 Info.plist 的 `AIMRemoteBaseURL` 展开，由
`APIEndpointConfiguration.remote` 读出。

xcconfig 把 `//` 当行注释，直接写 `http://主机/` 会被截断成 `http:`。真实写法是
`http:/$()/主机/`——`$()` 展开为空串，把两个斜杠隔开。模板里写明了这一点。

### 缺配置时崩，不回退

`remote` 读到空值就 `fatalError`，消息直接指回 xcconfig。不回退到本地栈：真机上
127.0.0.1 指向手机自己，回退只会变成一串认不出来源的连接失败。这是开发者配置错误，
崩得越早越响越好。

代价是模拟器不能碰这个属性。解法是把 `remote` 做成 `@autoclosure` 参数一路传到
`resolve`，只有真机分支和 `-remote` 分支才求值。这样新克隆的仓库不做任何配置也能跑
`make ios-build` 和 `make ios-test`。

`testProductionCallPathResolvesLocallyWhileTestsRun` 守着这条惰性：它走默认参数，
一旦有人把 `@autoclosure` 改回普通参数，无配置的构建机上这条会当场崩掉。

### 测试与文档

测试注入假地址 `http://remote.test`，不再依赖真实值，断言里也不再抄一份主机名。
`UserDefaults` 覆盖用例改用 RFC 5737 文档地址段 `192.0.2.10`，替掉原来的真实内网地址。

公开文档一律写 `<部署机 IP>`，部署步骤原样保留。真实地址与待办落到 `.gitignore`
排除的 `infrastructure/deploy/LOCAL.md`，公开 README 指明去哪看。

### 历史改写

`git filter-repo --replace-text` 把两个地址替换成不带尖括号的 token（尖括号在
Info.plist 的 XML 注释里虽合法，但历史版本太多，不值得赌），然后 5 个分支强推。

## 已知不能解决的部分

强推不会让 GitHub 删除旧提交——它们仍可按 SHA 直接访问，直到官方 GC；需要另外联系
GitHub Support 清理。fork 网络里的副本永久保留。代码搜索与第三方镜像可能已索引。

**真正的补救在服务器侧。** 见 `infrastructure/deploy/LOCAL.md` 的待办：确认生产
`.env` 已覆盖仓库里的 `aim-development-secret` 默认值、配域名 + HTTPS、收紧安全组、
处理开放注册。

## 验证

- `make ios-build` 通过；产物 Info.plist 的 `AIMRemoteBaseURL` 确为本地配置的值
- 移走本地 xcconfig 重建：零警告，该键展开为空串
- 移走本地 xcconfig 跑 `AimAppTests`：全部通过
- `git grep` 两个地址在跟踪文件中零命中
- 改写后 `git log -S` 在全历史中零命中
