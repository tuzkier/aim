# Eve Agent Runtime 技术验证记录

## 结论

当前 Gate：**PASS（Eve Runtime、FastAPI Tool Contract 与真实本地联调已落地）**。

本结论覆盖 Eve Runtime 的运行机制、安全边界、FastAPI Internal Tool API 契约和一次真实本地写入联调；不代表已经完成真实模型、生产 Workflow Store 或 iOS 客户端验收。任一生产前门槛失败，都应重新打开 ADR-0011 的 Runtime 选型。

## 验证范围

- 服务目录：`services/agent`
- Eve：`0.37.1`，锁文件精确固定
- Node：`24.x`；Eve 当前包要求 Node 24
- 本地模型：`EVE_USE_MOCK_MODEL=1` 的确定性模型，仅用于运行时 Gate，不作为生产模型
- 生产启动路径：`eve build` → `eve start`
- 业务事实：本服务没有 PostgreSQL 依赖、表模型或业务事实写入

## 证据

| 验证项 | 结果 | 证据 |
|---|---|---|
| Node/依赖可安装 | PASS | `npm ci` 成功；`package.json` 固定 Eve `0.37.1`、Node `24.x` |
| TypeScript 类型检查 | PASS | `npm run typecheck` |
| Eve 编译 | PASS | `npm run build`，0 diagnostics，Nitro 输出生成成功 |
| Docker 镜像 | PASS | `docker build --file services/agent/Dockerfile --tag aim-agent-runtime:gate services/agent` |
| 自托管启动 | PASS | `eve start --host 127.0.0.1 --port 2100`，health 返回 200 |
| 受保护路由默认拒绝 | PASS | 无三项 Aim Scope Header 请求 `/eve/v1/info` 返回 401；health 保持公开 |
| Session Context | PASS | `echo_context` 返回 `accountId=acct_hz_001`、`familyId=fam_001`、`pregnancyId=preg_001`，且 `sessionId` 与路由一致 |
| NDJSON 流 | PASS | 观察到 `session.started`、`turn.started`、`action.result`、`message.completed`、`session.waiting` 等事件 |
| Stream Cursor | PASS | 从 `startIndex=0` 与后续游标重读，事件 `meta.id` 稳定；事件 ID 无重复 |
| Continuation | PASS | Follow-up 使用同一 `sessionId`，`sequence=1`，`continuationToken` 保持一致 |
| 进程重启恢复 | PASS | 停止并重新启动服务后，同一 Session 重读出原有 turn `0/1` 和末尾 `session.waiting` |
| 根 Agent→专家 Subagent | PASS | 观察到 `subagent.called`、独立 `childSessionId`、`subagent.completed` |
| Subagent 工具隔离 | PASS | 根仅暴露 `echo_context`、`preview_task_change`；专家仅暴露 `echo_context` |
| 高权限默认工具禁用 | PASS | 编译清单禁用 `agent`、`bash`、`glob`、`grep`、`read_file`、`web_fetch`、`web_search`、`write_file`；专家同样禁用 |
| Workflow Callback | PASS | `eve start` 生成并监听 `POST /.well-known/workflow/v1/flow`，无必需请求头时返回 400，而非 404 |
| Eve Eval | PASS | `EVE_EVAL_AUTH_TOKEN=runtime-gate-token npm run eval -- --url http://127.0.0.1:2100 --strict --skip-report`，`runtime-gate` 4/4 gates |
| 真实模型供应商 | 未完成 | 当前环境没有 AI Gateway/供应商凭证；需要在候选中国大陆模型确定后单独做 Tool Calling 和结构化输出验证 |
| FastAPI Tool API | PASS | 7 个受控 Tool 路由、作用域重校验、审批门、版本冲突、幂等和审计调用记录；`services/api/tests/integration/agent_access/` 全部通过 |
| Eve 业务 Tool 适配层 | PASS | `npm run typecheck`、`npm run build`、`npm test`；工具从 Session Context 取作用域，不接受模型传入的身份 ID |
| Eve→FastAPI→PostgreSQL 真实联调 | PASS | `plan-change` 集成 eval：读取任务 → 生成变更预览 → Eve 持久化审批 → `update_task` 写入 PostgreSQL；审批恢复携带同一 Session Scope，重复调用复用同一 operation id |

## 当前运行时骨架

```text
HTTP Channel
  └─ aimSessionAuth
       └─ ctx.session.auth.current
       ├─ get_pregnancy_context      (read)
       ├─ list_tasks                 (read)
       ├─ get_guidance               (read)
       ├─ preview_task_change        (non-mutating preview)
       ├─ update_task / assign_task  (approval-gated writes)
       ├─ record_pregnancy_fact      (approval-gated write)
       ├─ undo_operation             (approval-gated write)
       └─ pregnancy-expert           (read-only Subagent)
```

鉴权当前使用三个显式请求头作为本地契约占位：

- `x-aim-account-id`
- `x-aim-family-id`
- `x-aim-pregnancy-id`

这不是生产身份方案。接入 FastAPI/JWT 或统一会话交换后，只替换 `agent/lib/auth.ts`，不改变 Tool 的 Session Context 读取方式。

自动化 eval 还支持显式设置 `EVE_EVAL_AUTH_TOKEN`，仅把匹配的 Bearer 映射到固定的非生产 fixture scope；未设置该变量时不会放宽鉴权。

## 生产前必须补齐

1. 选择并实测符合中国大陆数据边界的真实模型与凭证路径。
2. 为 Eve Workflow Store 选择持久化部署方案；当前本地默认 world 依赖 `.eve/.workflow-data`，容器必须挂载持久卷或切换兼容的 Workflow world。
3. 将 header 占位鉴权替换为 FastAPI 签发/验证的短期 Agent Session 凭证。
4. 将当前本地 Agent Scope Header 替换为 FastAPI 签发/验证的短期 Agent Session 凭证，并验证跨服务超时和重试策略。
5. 补 iOS 客户端的 NDJSON decoder、cursor 恢复、会话状态映射和审批交互；再用真实模型与生产 Workflow Store 做部署验收。

## 可复现命令

```bash
cd services/agent
PATH=/usr/local/bin:/opt/homebrew/bin:$PATH npm ci
PATH=/usr/local/bin:/opt/homebrew/bin:$PATH npm run typecheck
PATH=/usr/local/bin:/opt/homebrew/bin:$PATH npm run build
PATH=/usr/local/bin:/opt/homebrew/bin:$PATH EVE_USE_MOCK_MODEL=1 npm exec -- eve start --host 127.0.0.1 --port 2100
PATH=/usr/local/bin:/opt/homebrew/bin:$PATH EVE_RUNTIME_URL=http://127.0.0.1:2100 npm test

# 在 FastAPI 已以 8100 端口启动、并设置 AIM_API_INTERNAL_URL 与
# AGENT_SERVICE_SECRET 后，运行真实业务写入联调：
PATH=/usr/local/bin:/opt/homebrew/bin:$PATH \
EVE_EVAL_AUTH_TOKEN=runtime-gate-token \
AIM_RUN_INTEGRATION_EVAL=1 \
AIM_EVAL_ACCOUNT_ID=<account-id> \
AIM_EVAL_FAMILY_ID=<family-id> \
AIM_EVAL_PREGNANCY_ID=<pregnancy-id> \
npm exec -- eve eval plan-change --url http://127.0.0.1:2210 --strict --skip-report --timeout 30000 --json
```

## 参考

- [Eve self-hosting](https://github.com/vercel/eve/blob/main/docs/guides/deployment/self-hosting.md)
- [Eve sessions and streaming](https://github.com/vercel/eve/blob/main/docs/concepts/sessions-runs-and-streaming.md)
- [Eve auth and route protection](https://github.com/vercel/eve/blob/main/docs/guides/auth-and-route-protection.md)
- [Eve subagents](https://github.com/vercel/eve/blob/main/docs/subagents.mdx)
