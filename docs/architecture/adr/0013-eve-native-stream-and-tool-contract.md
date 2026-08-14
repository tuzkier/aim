# ADR-0013：使用 Eve 原生会话流与受控 Tool API

## 状态

已接受

## 背景

Eve 已被确定为独立 Agent Runtime。早期方案假设 FastAPI 提供 SSE 并转发 Agent 流，但 Eve 原生提供持久化会话、Continuation Token、Stream Cursor 和可恢复 NDJSON HTTP Stream。额外转换协议会丢失 Eve 的会话语义，并增加代理和恢复逻辑。

同时，Eve 不能直接访问业务数据库。Agent 对家庭、孕期、计划和待办的所有操作需要经过可鉴权、可幂等、可审查的业务边界。

## 决策

- iOS 直接使用 Eve 原生 HTTP 会话与 NDJSON Stream；
- iOS 持久化 `sessionId`、`continuationToken` 和 `streamIndex`；
- Agent 流不通过 FastAPI 代理，也不转换为 SSE；
- 统一入口将 `/eve/*` 和 `/.well-known/workflow/*` 原样路由到 Eve；
- FastAPI 仅提供普通 Public API 和受控 Internal Tool API；
- Eve Tool 从已验证 Session Context 获取账号与家庭身份，不能让模型提供租户身份；
- FastAPI 在每次 Tool 调用时重新验证业务权限；
- 写 Tool 使用 `sessionId + callId` 形成幂等键；
- Tool 成功结果是业务修改的唯一凭证，Agent 文本不作为成功凭证；
- Tool 返回最小化结构化结果和稳定机器错误；
- FastAPI OpenAPI 分别生成 Swift Public API Client 和 TypeScript Internal Tool Client。

本 ADR 修正 ADR-0009 中由 FastAPI 提供 Agent SSE 连接层的部分；ADR-0009 关于 FastAPI 作为业务 Web/API 底座的其他决定继续有效。

## 影响

### 正面

- 保留 Eve 的断线恢复和持久化会话能力；
- FastAPI 无需代理长连接或理解 Eve 内部事件；
- Agent 与业务事实通过明确 Tool Contract 隔离；
- Tool 权限、幂等和错误可以独立测试。

### 负面

- 需要手写并维护 Eve Swift Client；
- iOS 需要理解 Eve 会话游标和事件 Schema；
- 统一入口必须正确代理 Eve Workflow Callback 路径；
- Eve Beta 升级可能改变协议，需要通过契约测试发现。

### 中性

- 普通业务 API 仍使用 FastAPI REST/JSON；
- 若未来 Eve 提供官方 Swift SDK，可以替换手写 Client 而不改变业务领域。

## 备选方案

- FastAPI 代理并转换为 SSE：增加状态、延迟和恢复复杂度；
- iOS 只接收最终 Agent 结果：失去流式体验和审批交互；
- Eve 直接写 PostgreSQL：破坏 DDD、权限和业务事实边界。

## 参考

- https://github.com/vercel/eve/blob/main/docs/concepts/sessions-runs-and-streaming.md
- https://github.com/vercel/eve/blob/main/docs/guides/client/overview.mdx
- https://github.com/vercel/eve/blob/main/docs/tools/overview.mdx
- https://github.com/vercel/eve/blob/main/docs/guides/deployment/self-hosting.md
- [MVP 技术架构](../2026-08-14-mvp-technical-architecture.md)

