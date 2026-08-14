# ADR-0011：使用 Eve 作为独立 Agent Runtime 服务

## 状态

已接受

## 背景

业务服务已确定使用 Python、FastAPI 和 PostgreSQL，但 Agent 需要会话运行、流式事件、Skills、专业 Subagents、人工确认、可恢复执行及后续主动调度。自行建设这些 Runtime 能力会偏离产品核心；把 Agent 作为 FastAPI 内的普通库调用，又会让业务 API 承担 Agent 生命周期。

项目接受 Agent Runtime 使用独立语言和独立服务。Eve 提供文件化 Agent 定义、Skills、Tools、Subagents、持久化会话、可重连流式事件和 Schedules，与产品设想的成长规划 Agent、专业 Agent、Skill 和 Tool 结构一致。

Eve 当前仍处于 Beta，因此采用前必须验证其自托管、模型、鉴权、持久化和安全边界。第一轮 Runtime Gate 已完成，证据见 [Eve Runtime 技术验证记录](../eve-runtime-validation.md)。

## 决策

采用以下服务边界：

- FastAPI 业务服务负责账号、家庭、孕期档案、计划、待办、记录、权限和业务事务；
- Eve 作为独立 TypeScript/Node.js Agent Runtime 服务；
- Eve 负责 Agent 会话、流式事件、成长规划 Agent、专业 Subagents、Skills、人工确认及确有需要的 Schedules；
- PostgreSQL 中的结构化业务数据仍是唯一业务事实；Eve 的会话和工作流状态不能替代业务记录；
- Eve 不直接访问业务数据库，所有查询与修改必须调用 FastAPI 暴露的受控内部 Tool API；
- iOS 通过统一入口访问业务 API 和 Agent API，Agent 请求必须携带并校验账号、家庭和孕期上下文；
- 首个 MVP 不在 FastAPI 与 Eve 之间增加 Celery、Redis 或消息队列；
- Eve 默认部署在中国大陆的自托管环境中，并直连符合数据边界要求的模型服务，不默认依赖 Vercel 托管 Runtime 或 AI Gateway；
- 关闭与孕期业务无关的默认文件、Shell、网络和通用代理能力，只向 Agent 暴露经过约束的 Skills、知识和业务 Tools。

产品功能开发前先完成一次技术验证，至少证明：

1. Eve 可在目标自托管环境运行并在进程重启后恢复会话；
2. 可接入候选中国大陆模型并稳定完成 Tool Calling 和结构化输出；
3. iOS 或标准 HTTP 客户端可连接、断线重连并继续接收流式事件；
4. Eve 可以携带账号与家庭上下文安全调用 FastAPI Tool API；
5. 成长规划 Agent 可以调用一个孕产专业 Subagent，并只形成一份最终方案；
6. 默认高权限工具能够被关闭，未经授权的 Tool 调用会被拒绝；
7. Eve 升级或替换时不影响 FastAPI 的领域模型和 Tool 契约。

当前已通过的运行机制包括自托管启动、受保护 Session、Session Context、NDJSON Cursor、进程重启恢复、Subagent 隔离、默认高权限工具禁用和 Workflow Callback 路由。真实模型、生产 Workflow Store、FastAPI Tool API 和 iOS 客户端仍是后续门槛，不在本次 Gate 结论中提前宣称完成。

若关键验证不通过，重新打开 Agent Runtime 选型；FastAPI 业务服务与 Tool API 边界保持不变。

## 影响

### 正面

- 不从零建设 Agent 循环、持久化会话、流式恢复和 Subagent 机制；
- Agent 的文件化 Skills、Tools 和 Evals 适合由 Coding Agent 持续建设和审查；
- Agent 故障与普通业务 API 隔离；
- 不需要为了首个 MVP 先引入 Celery 和 Redis。

### 负面

- 项目同时维护 Python 与 TypeScript 两套运行时；
- FastAPI 与 Eve 之间需要清晰的 Tool API、身份传递、超时和幂等约定；
- Eve 处于 Beta，存在 API 变化、升级和自托管运行风险；
- Agent 会话状态与业务事实属于不同存储，需要防止两者边界混淆。

### 中性

- Eve 是可替换的 Agent Runtime，不是产品业务事实中心；
- Schedules、Subagents 和 Sandbox 等能力按产品需要启用，不因框架具备就全部使用。

## 备选方案

- FastAPI 内嵌 PydanticAI：保持全 Python 且集成简单，但会由应用自行补充持久化会话、流式恢复和调度；
- LangGraph 独立服务：可提供持久化工作流，但编排层更低，需要建设更多 Agent Harness 能力；
- 自建 Agent Runtime：控制力最高，但重复建设成本和长期维护风险不符合当前团队条件；
- Celery Agent Worker：适合后台任务执行，但本身不提供完整 Agent 会话、Skills、Subagents 和流式协议。

## 参考

- https://github.com/vercel/eve
- https://github.com/vercel/eve/blob/main/docs/reference/project-layout.md
- https://github.com/vercel/eve/blob/main/docs/concepts/sessions-runs-and-streaming.md
- https://github.com/vercel/eve/blob/main/docs/guides/deployment/self-hosting.md
- https://github.com/vercel/eve/blob/main/docs/subagents.mdx
