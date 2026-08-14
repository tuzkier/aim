import assert from "node:assert/strict";
import test from "node:test";
import updateTask from "../agent/tools/update_task.ts";

test("confirmed update task forwards only business inputs and server approval", async () => {
  const previousSecret = process.env.AGENT_SERVICE_SECRET;
  const previousBaseUrl = process.env.AIM_API_INTERNAL_URL;
  const previousFetch = globalThis.fetch;
  process.env.AGENT_SERVICE_SECRET = "test-agent-secret";
  process.env.AIM_API_INTERNAL_URL = "http://api.test";

  let request: Request | undefined;
  globalThis.fetch = async (input, init) => {
    request = new Request(input, init);
    return new Response(
      JSON.stringify({
        operation_id: "operation_write_001",
        status: "completed",
        summary: "已更新任务：预约产检",
        data: { task_id: "00000000-0000-4000-8000-000000000001", version: 2, status: "scheduled" },
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };

  const ctx = {
    session: {
      id: "wrun_write_session",
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
    callId: "call_write_001",
    abortSignal: AbortSignal.timeout(2_000),
  } as never;

  try {
    const result = (await updateTask.execute(
      {
        taskId: "00000000-0000-4000-8000-000000000001",
        action: "schedule",
        expectedVersion: 1,
        scheduledFor: "2026-08-21T09:00:00.000Z",
      },
      ctx,
    )) as { status: string };

    assert.equal(result.status, "completed");
    assert.ok(request);
    assert.deepEqual(await request.clone().json(), {
      task_id: "00000000-0000-4000-8000-000000000001",
      action: "schedule",
      expected_version: 1,
      scheduled_for: "2026-08-21T09:00:00.000Z",
      approved: true,
    });
    assert.equal((await request.clone().json()).family_id, undefined);
    assert.equal((await request.clone().json()).pregnancy_id, undefined);
  } finally {
    globalThis.fetch = previousFetch;
    if (previousSecret === undefined) delete process.env.AGENT_SERVICE_SECRET;
    else process.env.AGENT_SERVICE_SECRET = previousSecret;
    if (previousBaseUrl === undefined) delete process.env.AIM_API_INTERNAL_URL;
    else process.env.AIM_API_INTERNAL_URL = previousBaseUrl;
  }
});

test("write tools are configured for durable Eve approval", () => {
  assert.equal(typeof updateTask.approval, "function");
});
