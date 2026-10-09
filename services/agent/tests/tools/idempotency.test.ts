import assert from "node:assert/strict";
import test from "node:test";
import { callBusinessApi, BusinessApiError } from "../../agent/lib/business-api/client.ts";

const scope = {
  session: {
    id: "wrun_test_session",
    auth: {
      current: {
        attributes: {
          accountId: "acct_test",
          familyId: "fam_test",
          pregnancyId: "preg_test",
        },
      },
    },
  },
  callId: "call_same_001",
  abortSignal: AbortSignal.timeout(2_000),
} as never;

test("business client derives a stable scoped idempotency request", async () => {
  const previousSecret = process.env.AGENT_SERVICE_SECRET;
  const previousBaseUrl = process.env.AIM_API_INTERNAL_URL;
  const previousFetch = globalThis.fetch;
  process.env.AGENT_SERVICE_SECRET = "test-agent-secret";
  process.env.AIM_API_INTERNAL_URL = "http://api.test";

  const requests: Request[] = [];
  globalThis.fetch = async (input, init) => {
    requests.push(new Request(input, init));
    return new Response(
      JSON.stringify({
        operation_id: "operation_same_001",
        status: "completed",
        summary: "已读取当前孕期上下文",
        data: { pregnancy_id: "preg_test" },
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };

  try {
    const first = await callBusinessApi(scope, "/internal/agent-tools/get-pregnancy-context");
    const second = await callBusinessApi(scope, "/internal/agent-tools/get-pregnancy-context");

    assert.deepEqual(second, first);
    assert.equal(requests.length, 2);
    for (const request of requests) {
      assert.equal(request.headers.get("idempotency-key"), "call_same_001");
      assert.equal(request.headers.get("eve-session-id"), "wrun_test_session");
      assert.equal(request.headers.get("actor-account-id"), "acct_test");
      assert.equal(request.headers.get("family-id"), "fam_test");
      assert.equal(request.headers.get("pregnancy-id"), "preg_test");
      assert.equal(request.headers.get("service-authorization"), "Bearer test-agent-secret");
      assert.deepEqual(await request.clone().json(), {});
    }
  } finally {
    globalThis.fetch = previousFetch;
    if (previousSecret === undefined) delete process.env.AGENT_SERVICE_SECRET;
    else process.env.AGENT_SERVICE_SECRET = previousSecret;
    if (previousBaseUrl === undefined) delete process.env.AIM_API_INTERNAL_URL;
    else process.env.AIM_API_INTERNAL_URL = previousBaseUrl;
  }
});

test("business client exposes FastAPI approval and retry semantics", async () => {
  const previousSecret = process.env.AGENT_SERVICE_SECRET;
  const previousFetch = globalThis.fetch;
  process.env.AGENT_SERVICE_SECRET = "test-agent-secret";
  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({ error: { code: "approval_required", message: "确认后才会修改家庭计划" } }),
      { status: 409, headers: { "content-type": "application/json" } },
    );

  try {
    await assert.rejects(
      callBusinessApi(scope, "/internal/agent-tools/reschedule-task", { approved: false }),
      (error: unknown) => {
        assert.ok(error instanceof BusinessApiError);
        assert.equal(error.code, "approval_required");
        assert.equal(error.status, 409);
        assert.equal(error.retryable, false);
        return true;
      },
    );
  } finally {
    globalThis.fetch = previousFetch;
    if (previousSecret === undefined) delete process.env.AGENT_SERVICE_SECRET;
    else process.env.AGENT_SERVICE_SECRET = previousSecret;
  }
});

test("business client retries once when the runtime scope context is transiently unset", async () => {
  const previousSecret = process.env.AGENT_SERVICE_SECRET;
  const previousFetch = globalThis.fetch;
  process.env.AGENT_SERVICE_SECRET = "test-agent-secret";

  let attempt = 0;
  globalThis.fetch = async () => {
    attempt += 1;
    if (attempt === 1) {
      return new Response(JSON.stringify({ detail: "invalid agent scope" }), {
        status: 400,
        headers: { "content-type": "application/json" },
      });
    }
    return new Response(
      JSON.stringify({
        operation_id: "operation_retry_001",
        status: "completed",
        summary: "已读取当前孕期上下文",
        data: { pregnancy_id: "preg_test" },
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };

  try {
    const result = await callBusinessApi(scope, "/internal/agent-tools/get-pregnancy-context");
    assert.equal(attempt, 2);
    assert.equal(result.operationId, "operation_retry_001");
  } finally {
    globalThis.fetch = previousFetch;
    if (previousSecret === undefined) delete process.env.AGENT_SERVICE_SECRET;
    else process.env.AGENT_SERVICE_SECRET = previousSecret;
  }
});

test("business client does not retry a persistent scope failure or unrelated 400s", async () => {
  const previousSecret = process.env.AGENT_SERVICE_SECRET;
  const previousFetch = globalThis.fetch;
  process.env.AGENT_SERVICE_SECRET = "test-agent-secret";

  try {
    let attempt = 0;
    globalThis.fetch = async () => {
      attempt += 1;
      return new Response(JSON.stringify({ detail: "invalid agent scope" }), {
        status: 400,
        headers: { "content-type": "application/json" },
      });
    };

    await assert.rejects(
      callBusinessApi(scope, "/internal/agent-tools/get-pregnancy-context"),
      (error: unknown) => {
        assert.ok(error instanceof BusinessApiError);
        assert.equal(error.message, "invalid agent scope");
        return true;
      },
    );
    assert.equal(attempt, 2, "one retry, then give up");

    attempt = 0;
    globalThis.fetch = async () => {
      attempt += 1;
      return new Response(JSON.stringify({ detail: "task not found" }), {
        status: 400,
        headers: { "content-type": "application/json" },
      });
    };

    await assert.rejects(
      callBusinessApi(scope, "/internal/agent-tools/get-pregnancy-context"),
      (error: unknown) => {
        assert.ok(error instanceof BusinessApiError);
        assert.equal(error.message, "task not found");
        return true;
      },
    );
    assert.equal(attempt, 1, "unrelated 400s are not retried");
  } finally {
    globalThis.fetch = previousFetch;
    if (previousSecret === undefined) delete process.env.AGENT_SERVICE_SECRET;
    else process.env.AGENT_SERVICE_SECRET = previousSecret;
  }
});
