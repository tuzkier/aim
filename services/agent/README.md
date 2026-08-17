# Aim Agent Runtime

This service owns the Eve root Agent, pregnancy specialist Subagent, session
stream, and runtime capability boundaries. It does not own business facts or
connect to PostgreSQL.

## Local gate

Use Node.js 24.x (the current Eve package requires it):

```bash
PATH=/usr/local/bin:/opt/homebrew/bin:$PATH npm ci
EVE_USE_MOCK_MODEL=1 npm run dev
```

The local gate model is deterministic and exists only to exercise auth,
streaming, tool calls, and Subagent boundaries without credentials. Production
sets `EVE_USE_MOCK_MODEL=0` and supplies the configured model credentials. The
current server-side provider is DeepSeek through its OpenAI-compatible API:

```bash
EVE_USE_MOCK_MODEL=0
AIM_AGENT_MODEL=deepseek-chat
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_API_KEY= # keep this in a local .env or secret manager
```

The API key is injected into the Eve container only. It is never sent to iOS,
committed to the repository, or included in logs.

From the repository root, start Compose with the local env file so the live
provider selection is applied:

```bash
docker compose --env-file .env -f infrastructure/compose/compose.yaml up -d api eve
```

```bash
npm run typecheck
npm run build
EVE_RUNTIME_URL=http://127.0.0.1:2000 npm test
```

The runtime requires `x-aim-account-id`, `x-aim-family-id`, and
`x-aim-pregnancy-id` on every protected route until the FastAPI auth exchange
is wired in. Evals may additionally set `EVE_EVAL_AUTH_TOKEN`; that explicit
bearer is mapped to a fixed non-production fixture scope.

## FastAPI business boundary

Eve never connects to PostgreSQL. The business tools call the FastAPI internal
tool API with these environment variables:

```bash
AIM_API_INTERNAL_URL=http://127.0.0.1:8000
AGENT_SERVICE_SECRET=aim-agent-development-secret
```

Read tools (`get_pregnancy_context`, `list_tasks`, `list_records`, `get_guidance`) use the
authenticated Eve Session Context. Plan and fact mutations are gated by Eve's
durable human approval and send `approved=true` only after approval. FastAPI
re-checks family membership and pregnancy ownership, applies optimistic
versioning, and uses the Eve tool `callId` as its idempotency key.
