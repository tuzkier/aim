# aim

孕期 AI Agent App：以 Today、计划和家庭协作为主入口，Agent 通过受控 Tools 贯穿业务功能。

## 当前状态

- 产品与交互原型：`prototype/`
- 产品方案：`docs/plans/`
- 系统架构与 ADR：`docs/architecture/`
- Coding Agent 实施计划：`docs/plans/2026-08-14-pregnancy-core-implementation-plan.md`
- 当前第一阶段：FastAPI 业务闭环、Eve 受控工具联调与 SwiftUI 核心客户端骨架已完成；Simulator 验收待完整 Xcode 环境

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

第一阶段不要求 Xcode 才能运行 FastAPI、PostgreSQL 和 Eve；进入 iOS Task 之前需要安装完整 Xcode。
