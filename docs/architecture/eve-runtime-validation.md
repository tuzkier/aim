# Eve Agent Runtime 技术验证记录

## 结论

当前 Gate：**PASS（允许继续实现 FastAPI 业务边界和 Tool Contract）**。

本结论只覆盖 Eve Runtime 的运行机制和安全边界，不代表已经完成真实模型、生产 Workflow Store、FastAPI Internal Tool API 或 iOS 客户端验收。这些工作仍按实施计划继续完成；任一生产前门槛失败，都应重新打开 ADR-0011 的 Runtime 选型。

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
| FastAPI Tool API | 未完成 | 下一阶段实现；Eve 只保留受控 Tool 适配层，不直连 PostgreSQL |

## 当前运行时骨架

```text
HTTP Channel
  └─ aimSessionAuth
       └─ ctx.session.auth.current
            ├─ echo_context              (read)
            ├─ preview_task_change        (non-mutating preview)
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
4. 实现 FastAPI Internal Tool API、幂等键、超时、审计和业务权限校验。
5. 在 iOS 客户端实现 NDJSON decoder、cursor 恢复和会话状态映射。

## 可复现命令

```bash
cd services/agent
PATH=/usr/local/bin:/opt/homebrew/bin:$PATH npm ci
PATH=/usr/local/bin:/opt/homebrew/bin:$PATH npm run typecheck
PATH=/usr/local/bin:/opt/homebrew/bin:$PATH npm run build
PATH=/usr/local/bin:/opt/homebrew/bin:$PATH EVE_USE_MOCK_MODEL=1 npm exec -- eve start --host 127.0.0.1 --port 2100
PATH=/usr/local/bin:/opt/homebrew/bin:$PATH EVE_RUNTIME_URL=http://127.0.0.1:2100 npm test
```

## 参考

- [Eve self-hosting](https://github.com/vercel/eve/blob/main/docs/guides/deployment/self-hosting.md)
- [Eve sessions and streaming](https://github.com/vercel/eve/blob/main/docs/concepts/sessions-runs-and-streaming.md)
- [Eve auth and route protection](https://github.com/vercel/eve/blob/main/docs/guides/auth-and-route-protection.md)
- [Eve subagents](https://github.com/vercel/eve/blob/main/docs/subagents.mdx)
