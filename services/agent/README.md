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
removes `EVE_USE_MOCK_MODEL` and supplies the configured model credentials.

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

Read tools (`get_pregnancy_context`, `list_tasks`, `get_guidance`) use the
authenticated Eve Session Context. Plan and fact mutations are gated by Eve's
durable human approval and send `approved=true` only after approval. FastAPI
re-checks family membership and pregnancy ownership, applies optimistic
versioning, and uses the Eve tool `callId` as its idempotency key.
