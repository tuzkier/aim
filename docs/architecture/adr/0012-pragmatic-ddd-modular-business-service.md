# ADR-0012：FastAPI 业务服务采用轻量 DDD 模块化单体

## 状态

已接受

## 背景

产品包含账号、家庭、孕期、计划、待办、知识安全和 Agent Tool 等不同业务责任。若按技术类型建立全局 Router、Service 和 Model 目录，边界会随功能增长迅速混杂；若直接拆成微服务，又会给单人开发和 MVP 带来不必要的部署与一致性成本。

## 决策

FastAPI 业务服务采用轻量 DDD 模块化单体：

- 限界上下文为 Identity & Access、Family、Pregnancy Journey、Planning、Guidance & Safety 和 Agent Access；
- 每个上下文内部按 Domain、Application、Adapters 分层；
- Platform 与 Bootstrap 负责基础设施和依赖装配；
- Domain 使用纯 Python，不依赖 FastAPI、Pydantic 和 SQLAlchemy；
- 上下文之间通过 ID、Application Contract 或进程内事件协作，不导入对方 ORM Model；
- PostgreSQL 由单个服务拥有，迁移使用统一 Alembic 流；
- 写入围绕聚合和 Unit of Work，读取允许通过 Composition 层组装；
- 自动化架构测试检查依赖方向和跨上下文边界；
- 不要求为简单数据强行创建所有战术模式或目录。

## 影响

### 正面

- 领域规则、框架代码和持久化代码边界清晰；
- Coding Agent 可以依据目录和测试判断修改范围；
- 保持单体部署、事务和调试简单；
- 未来确有需要时可以按上下文提取服务。

### 负面

- DTO、领域对象和 ORM Model 之间需要显式转换；
- 团队必须维护上下文语言和聚合边界；
- 过度抽象仍可能产生样板，需要持续控制。

### 中性

- DDD 用于业务服务，不要求 iOS 和 Eve 复制同一分层；
- 同一个 PostgreSQL 不代表上下文可以任意跨表写入。

## 备选方案

- 全局三层架构：初期文件少，但业务边界容易在 Service 和 ORM 中混合；
- 每个上下文独立微服务：当前团队和规模不足以覆盖分布式成本；
- 完整六边形与 CQRS 平台：能力过重，不适合 MVP。

## 参考

- [MVP 技术架构](../2026-08-14-mvp-technical-architecture.md)
- [Monorepo 初始目录规范](../2026-08-14-monorepo-structure.md)

