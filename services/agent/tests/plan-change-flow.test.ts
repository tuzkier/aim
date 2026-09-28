import assert from "node:assert/strict";
import test from "node:test";
import completeTask from "../agent/tools/complete_task.ts";
import rescheduleTask from "../agent/tools/reschedule_task.ts";
import undoOperation from "../agent/tools/undo_operation.ts";

const ctx = {
  session: {
    id: "wrun_write_session",
    auth: {
      current: {
        attributes: { accountId: "acct_test", familyId: "fam_test", pregnancyId: "preg_test" },
      },
    },
  },
  callId: "call_write_001",
  abortSignal: AbortSignal.timeout(2_000),
} as never;

async function capture(run: () => unknown): Promise<Request> {
  const previousSecret = process.env.AGENT_SERVICE_SECRET;
  const previousBaseUrl = process.env.AIM_API_INTERNAL_URL;
  const previousFetch = globalThis.fetch;
  process.env.AGENT_SERVICE_SECRET = "test-agent-secret";
  process.env.AIM_API_INTERNAL_URL = "http://api.test";
  let request: Request | undefined;
  globalThis.fetch = async (input, init) => {
    request = new Request(input, init);
    return new Response(
      JSON.stringify({ operation_id: "op_1", status: "completed", summary: "ok", data: {} }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };
  try {
    await (run() as Promise<unknown>);
  } finally {
    globalThis.fetch = previousFetch;
    if (previousSecret === undefined) delete process.env.AGENT_SERVICE_SECRET;
    else process.env.AGENT_SERVICE_SECRET = previousSecret;
    if (previousBaseUrl === undefined) delete process.env.AIM_API_INTERNAL_URL;
    else process.env.AIM_API_INTERNAL_URL = previousBaseUrl;
  }
  assert.ok(request);
  return request;
}

const TASK = "00000000-0000-4000-8000-000000000001";

test("complete_task executes directly", async () => {
  assert.equal(completeTask.approval, undefined);
  const request = await capture(() =>
    completeTask.execute({ taskId: TASK, expectedVersion: 1 }, ctx),
  );
  assert.equal(request.url, "http://api.test/internal/agent-tools/complete-task");
  assert.deepEqual(await request.json(), { task_id: TASK, expected_version: 1 });
});

test("reschedule_task is gated and forwards server approval", async () => {
  assert.equal(typeof rescheduleTask.approval, "function");
  const request = await capture(() =>
    rescheduleTask.execute(
      { taskId: TASK, expectedVersion: 2, kind: "delay", at: "2026-10-09T09:00:00.000Z" },
      ctx,
    ),
  );
  assert.equal(request.url, "http://api.test/internal/agent-tools/reschedule-task");
  assert.deepEqual(await request.json(), {
    task_id: TASK,
    expected_version: 2,
    kind: "delay",
    at: "2026-10-09T09:00:00.000Z",
    approved: true,
  });
});

test("undo_operation needs only the operation id and no approval", async () => {
  assert.equal(undoOperation.approval, undefined);
  const request = await capture(() =>
    undoOperation.execute({ operationId: "11111111-1111-4111-8111-111111111111" }, ctx),
  );
  assert.equal(request.url, "http://api.test/internal/agent-tools/undo-operation");
  assert.deepEqual(await request.json(), {
    operation_id: "11111111-1111-4111-8111-111111111111",
  });
});

test("tools refuse to run without a pregnancy profile, in Chinese", async () => {
  const noPregnancy = {
    ...(ctx as object),
    session: {
      id: "wrun_x",
      auth: { current: { attributes: { accountId: "a", familyId: "f", pregnancyId: "" } } },
    },
  } as never;
  await assert.rejects(
    () => completeTask.execute({ taskId: TASK, expectedVersion: 1 }, noPregnancy) as Promise<unknown>,
    /还没有建立孕期档案/,
  );
});
