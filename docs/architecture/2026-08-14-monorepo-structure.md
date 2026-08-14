# 孕期 AI Agent App Monorepo 初始目录规范

## 1. 目的

本规范定义 MVP 初始化时的目录、所有权和依赖边界。它不是要求提前创建所有空模块；只有进入当前实施范围的目录才实际创建。

## 2. 根目录

```text
aim/
├── apps/
│   └── ios/
├── services/
│   ├── api/
│   └── agent/
├── contracts/
│   ├── public-api/
│   └── agent-tools/
├── content/
│   ├── pregnancy-tasks/
│   ├── safety-rules/
│   └── hangzhou/
├── infrastructure/
│   ├── compose/
│   └── deployment/
├── scripts/
├── docs/
├── Makefile
├── .env.example
└── README.md
```

### 2.1 apps/ios

唯一 iOS App。不得直接读取服务端数据库或 Eve 内部存储。

### 2.2 services/api

FastAPI DDD 业务服务，拥有 PostgreSQL 业务表、Public API、Internal Tool API 和 OpenAPI 契约生成。

### 2.3 services/agent

Eve Agent Runtime，拥有 Agent instructions、Skills、Tools、Subagents、Evals 和运行配置。不得拥有业务事实表。

### 2.4 contracts

保存可审查的 API 契约输入或快照，不保存手写跨语言业务实现。生成产物是否提交由初始化阶段根据构建稳定性决定。

### 2.5 content

保存结构化、版本化的阶段任务、安全规则和杭州资料。内容需要 Schema、来源和版本。Eve 不直接把这些文件当作业务事实，必须通过 Guidance Tool 获取已发布内容。

### 2.6 infrastructure

只包含本地 Compose、部署配置和运行说明，不包含业务代码。

## 3. FastAPI 目录

```text
services/api/
├── pyproject.toml
├── alembic.ini
├── migrations/
├── src/aim_api/
│   ├── main.py
│   ├── bootstrap.py
│   ├── kernel/
│   ├── platform/
│   │   ├── config/
│   │   ├── database/
│   │   ├── auth/
│   │   ├── observability/
│   │   └── http/
│   ├── composition/
│   │   └── today/
│   └── contexts/
│       ├── identity/
│       ├── family/
│       ├── pregnancy/
│       ├── planning/
│       ├── guidance/
│       └── agent_access/
└── tests/
    ├── architecture/
    ├── integration/
    └── contract/
```

上下文模板：

```text
contexts/planning/
├── domain/
│   ├── entities/
│   ├── value_objects/
│   ├── services/
│   ├── policies/
│   ├── events/
│   └── errors.py
├── application/
│   ├── commands/
│   ├── queries/
│   ├── ports/
│   ├── dto/
│   └── services/
└── adapters/
    ├── inbound/http/
    └── outbound/persistence/
        ├── models.py
        ├── repositories.py
        └── mappers.py
```

目录不为空时才创建。简单上下文可以减少子目录，但依赖方向不能改变。

## 4. Eve 目录

```text
services/agent/
├── package.json
├── tsconfig.json
├── agent/
│   ├── agent.ts
│   ├── instructions/
│   ├── channels/eve.ts
│   ├── tools/
│   ├── skills/
│   ├── subagents/
│   │   └── pregnancy-expert/
│   ├── hooks/
│   ├── lib/
│   │   ├── business-api/
│   │   ├── auth/
│   │   └── context/
│   └── instrumentation.ts
├── evals/
└── tests/
```

规则：

- 根 Agent 是成长规划 Agent；
- 专业 Subagent 默认只拥有只读 Tools；
- Tool 文件名即模型可见名称，命名必须稳定；
- Skills 只描述工作程序，不复制业务事实；
- 高权限默认 Tools 明确关闭；
- `lib/business-api` 只通过生成的 Internal Tool API Client 访问 FastAPI；
- Schedules、Sandbox 和 Connections 未进入需求时不创建。

## 5. iOS 目录

```text
apps/ios/AimApp/
├── App/
├── Core/
│   ├── Auth/
│   ├── Networking/
│   ├── Persistence/
│   ├── DesignSystem/
│   └── Observability/
├── Clients/
│   ├── BusinessAPIClient/
│   └── EveClient/
├── Features/
│   ├── Onboarding/
│   ├── Today/
│   ├── Plan/
│   ├── Agent/
│   └── Family/
├── Generated/OpenAPI/
├── Resources/
└── Tests/
```

Feature 模板：

```text
Features/Today/
├── TodayView.swift
├── TodayStore.swift
├── TodayModels.swift
├── TodayDependencies.swift
└── TodayTests.swift
```

首期保持一个 App Target，不为每个 Feature 建 Swift Package。Generated API 类型不得直接作为 SwiftUI View State。

## 6. 契约生成

```text
FastAPI Public OpenAPI
→ contracts/public-api/openapi.json
→ Swift OpenAPI Client

FastAPI Internal Tool OpenAPI
→ contracts/agent-tools/openapi.json
→ TypeScript Client
```

契约变更必须经过：

1. OpenAPI 生成；
2. 变更差异检查；
3. Swift Client 编译；
4. TypeScript Client 编译；
5. 契约测试通过。

## 7. 根级命令

```text
make dev          # 启动 PostgreSQL、FastAPI、Eve
make test         # 全部可自动运行的测试
make contracts    # 生成并校验 OpenAPI Client
make lint         # Python、TypeScript、Swift 静态检查
make verify       # 提交前完整验证
```

具体底层命令由各服务自己的工具管理，根 Makefile 只负责编排，不复制依赖配置。

## 8. 禁止事项

- Eve 或 iOS 直接连接 PostgreSQL；
- FastAPI Domain 导入 FastAPI、Pydantic、SQLAlchemy；
- 上下文导入其他上下文 ORM Model；
- Agent Tool 绕过 Application Use Case；
- 将家庭、孕期和任务实体复制到共享 Kernel；
- 手工维护与 OpenAPI 重复的跨语言 DTO；
- 为未来功能提前创建空微服务、空 Subagent 或空 Schedules；
- 在仓库中提交真实密钥或用户健康资料。

