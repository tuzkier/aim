# 部署说明

生产环境：阿里云 ECS `REDACTED_HOST`（Alibaba Cloud Linux 3，2C/1.8G）

## 目录约定（服务器）

- `/opt/aim/app` —— 代码（由 `git archive` 打包上传解压）
- `/opt/aim/app/.env` —— 生产环境变量，权限 600，**不在版本库中**
- `/opt/aim/backups` —— 每日 pg_dump，保留 7 天
- `/etc/nginx/conf.d/aim.conf` —— 反向代理，来自 `nginx-aim.conf`

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

限流：`/api/v1/auth/demo-session` 每 IP 5 次/分钟；其余接口 20 次/秒。

## iOS 接入

App 默认连这个环境，规则在 `apps/ios/AimApp/Core/Networking/APIEndpointConfiguration.swift`。

因为后端是纯 IP 且无 TLS，`apps/ios/AimApp/Resources/Info.plist` 里开了
`NSAllowsArbitraryLoads`。ATS 的 `NSExceptionDomains` **只接受域名、不接受 IP**，
所以没法只对这一个地址放行。**上架前必须**给后端配域名 + HTTPS，然后删掉整个
`NSAppTransportSecurity` 段。

排查提示：模拟器上残留的 `aim.apiBaseURL` 覆盖值优先级最高，独立于 App 容器保存，
卸载重装都清不掉，会让 App 静默连到别的后端。用
`xcrun simctl spawn booted defaults delete com.aim.pregnancy` 清除。

## 安全现状

`DEV_AUTH_ENABLED=true` 是当前**唯一**登录方式，无短信校验，任何人用任意手机号
即可创建账号。仅适用于验证阶段；接入真实用户前必须先实现正式鉴权。
