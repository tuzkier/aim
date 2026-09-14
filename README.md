# aim

孕期 AI Agent App：以「孕期」（今天总控 + 可进入的完整时间线）、资料库、AIM 与家庭为四个主入口，Agent 通过受控 Tools 贯穿业务功能。

## 当前状态

- 产品与交互原型：`prototype/`
- 产品方案：`docs/plans/`
- 系统架构与 ADR：`docs/architecture/`
- Coding Agent 实施计划：`docs/plans/2026-08-14-pregnancy-core-implementation-plan.md`
- 当前第一阶段：FastAPI 业务闭环、Eve 受控工具联调与 SwiftUI 核心客户端骨架已完成；iOS Simulator 与 Docker 本地栈均已具备可复现验证入口

## 目录边界

- `apps/ios`：原生 SwiftUI App
- `services/api`：FastAPI DDD 业务服务和 PostgreSQL 事实中心
- `services/agent`：独立 Eve Agent Runtime，不拥有业务事实表
- `contracts`：Public API 与 Internal Tool API 契约
- `content`：版本化孕期任务、安全规则和杭州资料
- `infrastructure`：本地 Compose 与部署配置

## 常用命令

```bash
make dev
make test
make contracts
make lint
make verify
```

`make dev` 会在 Docker 中启动 PostgreSQL、FastAPI 和 Eve。默认入口为：FastAPI `http://127.0.0.1:8100`、Eve `http://127.0.0.1:2210`、PostgreSQL `127.0.0.1:55434`。

## iOS 连接哪个后端

**真机装的包连部署在阿里云的验证环境**（Nginx 按路径前缀把 `/api/v1/*` 和
`/eve/v1/*` 分流到两个服务）；**模拟器和测试一律连本地 `make dev` 起的栈**。
要拿模拟器验线上，在 Xcode scheme 的 Run → Arguments 里加 `-remote`；反过来让真机
连本地栈用 `-local`。也可以写 `UserDefaults` 的 `aim.apiBaseURL` / `aim.eveBaseURL`
做临时覆盖，优先级最高。规则见
`apps/ios/AimApp/Core/Networking/APIEndpointConfiguration.swift`。

部署环境的真实地址不在版本库里。打真机包前先复制
`apps/ios/AimApp/Config/Endpoints.local.xcconfig.example` 为
`Endpoints.local.xcconfig` 并填入地址，否则 App 一启动就会崩并提示这件事；
模拟器不需要这一步。地址和部署细节见 `infrastructure/deploy/README.md`。

如果 App 连到了意料之外的后端，先排查模拟器上残留的覆盖值 —— 它优先级最高，
独立于 App 容器保存，卸载重装和 `-reset-session` 都清不掉：

```bash
xcrun simctl spawn booted defaults delete com.aim.pregnancy
```Eve 默认使用确定性 Mock Model；接入真实模型前请通过环境变量覆盖，不要把凭证写入 Compose 文件。

iOS 首屏是手机号 + 密码的注册／登录，注册时选择家庭角色（妈妈／爸爸／其他家人）和称呼。进入后可录入预产期或末次月经，Aim 按 280 天互相换算并生成孕期计划。不发送短信；密码找回靠服务器上的 `services/api/scripts/reset_password.py`。
