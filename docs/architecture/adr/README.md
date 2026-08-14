# 架构决策记录

本目录记录孕期 AI Agent App 已确认的关键架构决策。

| ADR | 决策 | 状态 |
|---|---|---|
| [0001](0001-native-ios-first.md) | 首期使用 SwiftUI 原生 iOS | 已接受 |
| [0002](0002-family-space-and-member-identities.md) | 独立账号通过家庭身份加入家庭空间 | 已接受 |
| [0003](0003-modular-monolith-with-agent-workers.md) | 模块化单体配合 Agent 后台任务进程 | 已被 0011 取代 |
| [0004](0004-unified-agent-runtime-and-tool-gateway.md) | 统一 Agent Runtime 与 Tool Gateway | 已接受 |
| [0005](0005-structured-facts-as-source-of-truth.md) | 结构化业务事实为唯一真相 | 已接受 |
| [0006](0006-mainland-china-data-processing.md) | 中国大陆为默认数据处理边界 | 已接受 |
| [0007](0007-no-healthkit-in-first-release.md) | 首期不接 HealthKit | 已接受 |
| [0008](0008-first-release-security-baseline.md) | 首期采用必要安全底线 | 已接受 |
| [0009](0009-fastapi-web-api-foundation.md) | 使用 FastAPI 作为 Web/API 技术底座 | 已接受，流式部分由 0013 修正 |
| [0010](0010-postgresql-sqlalchemy-alembic.md) | 使用 PostgreSQL、SQLAlchemy 2.0 与 Alembic | 已接受 |
| [0011](0011-eve-independent-agent-runtime.md) | 使用 Eve 作为独立 Agent Runtime 服务 | 已接受 |
| [0012](0012-pragmatic-ddd-modular-business-service.md) | FastAPI 业务服务采用轻量 DDD 模块化单体 | 已接受 |
| [0013](0013-eve-native-stream-and-tool-contract.md) | 使用 Eve 原生会话流与受控 Tool API | 已接受 |
