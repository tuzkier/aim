# 部署说明

生产环境：阿里云 ECS `<部署机 IP>`（Alibaba Cloud Linux 3，2C/1.8G）

> **地址不在版本库里。** 这是个公开仓库，主机地址、SSH 入口这类信息写在未跟踪的
> `infrastructure/deploy/LOCAL.md`，iOS 端的地址写在未跟踪的
> `apps/ios/AimApp/Config/Endpoints.local.xcconfig`。下文所有 `<部署机 IP>` 都指
> LOCAL.md 里记的那一个。

## 目录约定（服务器）

- `/opt/aim/app` —— 代码（由 `git archive` 打包上传解压）
- `/opt/aim/app/.env` —— 生产环境变量，权限 600，**不在版本库中**
- `/opt/aim/backups` —— 每日 pg_dump，保留 7 天
- `/etc/nginx/conf.d/aim.conf` —— 反向代理，来自 `nginx-aim.conf`

## 部署

```bash
infrastructure/deploy/deploy.sh <部署机 IP>
```

打包当前提交（`git archive`，所以工作区必须干净）、上传、构建、起服务，然后验证：
网关与 API 健康、**无票访问 Eve 返回 401**、**自报 `x-aim-*` 头也返回 401**。
最后那两条是鉴权修复的核心断言——身份只能从签名会话票推导。

api 与 eve 必须同批部署：eve 的鉴权依赖 api 的
`/internal/agent-tools/resolve-session`，先起 eve 会让所有 agent 请求 401。
脚本用一次 `compose up` 保证这个次序。

> **eve 升级会让升级前创建的对话读不回来**（容器日志里的 `CORRUPTED_EVENT_LOG`）。
> 会话目录里条目还在，内容没了。客户端会显示「这段对话的内容已不可用」，不白屏。

## 启停

```bash
cd /opt/aim/app/infrastructure/compose
docker compose --env-file /opt/aim/app/.env -f compose.yaml -f compose.prod.yaml up -d
docker compose --env-file /opt/aim/app/.env -f compose.yaml -f compose.prod.yaml ps
docker compose --env-file /opt/aim/app/.env -f compose.yaml -f compose.prod.yaml logs -f api
```

**切勿加 `-v`**：`docker compose down -v` 会删除 `postgres-data` 卷，数据不可恢复。

## 国内网络注意事项

这台服务器上以下外网**不可达**，部署时必须绕开：

- `hub.docker.com` / `registry-1.docker.io` —— 已在 `/etc/docker/daemon.json` 配置 `docker.1ms.run` 镜像加速
- `pypi.org` / `files.pythonhosted.org` —— 通过 `compose.prod.yaml` 的 `PIP_INDEX_URL` build arg 指向阿里云镜像站

可达：GitHub、npm 官方源、DeepSeek API。

拉取基础镜像较慢（node:24 约 3 分钟），不要用短超时打断，否则 dockerd 会
`context canceled` 并清理已下载的层，前功尽弃。

## 对外接口

Nginx 80 端口按路径前缀分流，两个服务合并在同一域名下：

| 路径 | 后端 |
|---|---|
| `/health` | Nginx 自身，网关探活 |
| `/api/v1/*` | api 容器 `127.0.0.1:8100` |
| `/eve/v1/*` | eve 容器 `127.0.0.1:2210`，关闭缓冲以支持 SSE |

限流：`/api/v1/auth/` 前缀（注册与登录）每 IP 5 次/分钟；其余接口 20 次/秒。

## iOS 接入

**只有装到真机上的包才连这个环境**；模拟器和 UI 测试一律连开发机的本地 Compose 栈。
规则在 `apps/ios/AimApp/Core/Networking/APIEndpointConfiguration.swift`，判据是编译期的
`targetEnvironment(simulator)`，不是启动参数——参数会忘记加，而忘记的代价是测试数据
默默写进生产库（曾因此在生产库堆了 253 个测试账号）。

跑 UI 测试前先起本地栈，否则用例会连不上：

```bash
docker compose --env-file .env -f infrastructure/compose/compose.yaml up -d
```

需要拿模拟器验线上时，加 `-remote` 启动参数。

真实地址由构建期注入，不在版本库里。打真机包（或用 `-remote`）之前先做一次：

```bash
cp apps/ios/AimApp/Config/Endpoints.local.xcconfig{.example,}
```

然后填入 `AIM_REMOTE_BASE_URL`。注意 xcconfig 里 `//` 是行注释，得写成
`http:/$()/主机/`，模板里有说明。没配置就打真机包的话，App 一启动就会崩，
崩溃信息直接指回这一步——这比静默连错后端好排查。

因为后端是纯 IP 且无 TLS，`apps/ios/AimApp/Resources/Info.plist` 里开了
`NSAllowsArbitraryLoads`。ATS 的 `NSExceptionDomains` **只接受域名、不接受 IP**，
所以没法只对这一个地址放行。**上架前必须**给后端配域名 + HTTPS，然后删掉整个
`NSAppTransportSecurity` 段。

排查提示：模拟器上残留的 `aim.apiBaseURL` 覆盖值优先级最高，独立于 App 容器保存，
卸载重装都清不掉，会让 App 静默连到别的后端。用
`xcrun simctl spawn booted defaults delete com.aim.pregnancy` 清除。

## 定时任务

注销账号有 30 天缓冲期，到期删除由脚本完成。服务器上加一条 crontab（每天 04:00）：

```
0 4 * * * docker exec -i aim-api-1 python scripts/purge_deleted_accounts.py >> /var/log/aim-purge.log 2>&1
```

先用 `--dry-run` 看一眼会删哪些账号再正式启用。

## 上架前清单

按顺序，前两项周期最长，先启动：

1. **域名 + HTTPS**：给后端配域名和证书，nginx 监听 443；`apps/ios/AimApp/Config/Endpoints.local.xcconfig` 的 `AIM_REMOTE_BASE_URL` 改成 `https://…`；然后删掉 `apps/ios/AimApp/Resources/Info.plist` 里整个 `NSAppTransportSecurity` 段。生产后端还是裸 IP 时**不能**删。
2. **ICP 备案**：域名备案 + App 备案，主体须与 Apple 开发者账号主体一致。
3. **Apple Developer Program** 付费账号；`apps/ios/AimApp.xcodeproj/project.pbxproj` 的 `DEVELOPMENT_TEAM` 换成该团队。
4. 部署上面的 crontab。
5. **App Store Connect**：隐私政策 URL 填 `https://<域名>/legal/privacy.html`；隐私标签勾选「手机号」「用户 ID」「健康与健身」「其他用户内容」，均为「与用户关联」「用于 App 功能」，不用于追踪；审核备注附一个测试账号，并说明医疗免责声明在用户协议与 AIM 页面头部两处。
6. 每次上传新构建前递增 `CURRENT_PROJECT_VERSION`（pbxproj 里两处）。

## 安全现状

登录方式是手机号 + 密码（argon2id）。**注册开放**：任何人都能创建账号——这是
2026-08-25 知情下的选择，见 `docs/superpowers/specs/2026-08-25-password-auth-design.md`。

**仍然是明文 HTTP**，密码在链路上是明文的。接入真实用户前必须先配域名 + HTTPS，
并删掉 `apps/ios/AimApp/Resources/Info.plist` 里的 `NSAppTransportSecurity` 段。

忘记密码没有自助路径，用服务器上的脚本重置：

```bash
docker exec -i aim-api-1 python scripts/reset_password.py 13800000000 新密码
```
