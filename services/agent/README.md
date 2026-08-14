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
