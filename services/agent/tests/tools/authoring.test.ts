import assert from "node:assert/strict";
import test from "node:test";
import createRecord from "../../agent/tools/create_record.ts";
import createTask from "../../agent/tools/create_task.ts";
import deleteTask from "../../agent/tools/delete_task.ts";
import updateTask from "../../agent/tools/update_task.ts";

const scope = {
  session: {
    id: "wrun_authoring_session",
    auth: {
      current: {
        attributes: {
          accountId: "acct_scope_only",
          familyId: "fam_scope_only",
          pregnancyId: "preg_scope_only",
        },
      },
    },
  },
  callId: "call_authoring_001",
  abortSignal: AbortSignal.timeout(2_000),
} as never;

// defineTool 的 execute 返回 Promise | AsyncIterable 联合类型（工具可以流式产出），
// 这里的工具都是一次性返回，所以统一按 Promise 处理。
async function withStubbedApi(
  data: Record<string, unknown>,
  run: () => unknown,
): Promise<{ result: unknown; request: Request | undefined }> {
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
        operation_id: "operation_authoring_001",
        status: "completed",
        summary: "已添加待办",
        data,
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };
  try {
    return { result: await (run() as Promise<unknown>), request };
  } finally {
    globalThis.fetch = previousFetch;
    if (previousSecret === undefined) delete process.env.AGENT_SERVICE_SECRET;
    else process.env.AGENT_SERVICE_SECRET = previousSecret;
    if (previousBaseUrl === undefined) delete process.env.AIM_API_INTERNAL_URL;
    else process.env.AIM_API_INTERNAL_URL = previousBaseUrl;
  }
}

test("create_task posts the to-do without asserting its own approval", async () => {
  const { result, request } = await withStubbedApi(
    { task_id: "11111111-1111-1111-1111-111111111111", title: "预约产检" },
    () =>
      createTask.execute(
        { title: "预约产检", description: "本周内完成" },
        scope,
      ),
  );

  assert.equal((result as { status: string }).status, "completed");
  assert.equal(request?.url, "http://api.test/internal/agent-tools/create-task");

  // 「直接执行」档由服务端的 DIRECT_EXECUTION_TOOLS 声明，工具不该自称已获批准——
  // 否则「执行前确认」那一档只要带上这个标志就能绕过。
  const body = (await request?.clone().json()) as Record<string, unknown>;
  // 未提供的可选字段会被 JSON 序列化丢掉，所以断言的是实际发出的键集合。
  assert.deepEqual(body, { title: "预约产检", description: "本周内完成" });
  assert.equal("approved" in body, false);
});

test("create_task is not gated by an approval request", () => {
  assert.equal(createTask.approval, undefined);
  assert.equal(createRecord.approval, undefined);
  assert.equal(deleteTask.approval, undefined);
});

test("update_task keeps its approval gate", () => {
  // 修改既有计划属于「执行前确认」档，放开新建不能顺手把它也放开。
  assert.notEqual(updateTask.approval, undefined);
});

test("create_record maps note content onto the gateway payload", async () => {
  const { request } = await withStubbedApi(
    { record_id: "22222222-2222-2222-2222-222222222222" },
    () =>
      createRecord.execute(
        { recordType: "note", content: "记得带既往报告" },
        scope,
      ),
  );

  assert.equal(request?.url, "http://api.test/internal/agent-tools/create-record");
  const body = (await request?.clone().json()) as Record<string, unknown>;
  assert.equal(body.record_type, "note");
  assert.equal(body.content, "记得带既往报告");
});

test("delete_task targets the undo endpoint", async () => {
  const { request } = await withStubbedApi({ task_id: "33333333-3333-3333-3333-333333333333" }, () =>
    deleteTask.execute({ taskId: "33333333-3333-3333-3333-333333333333" }, scope),
  );

  assert.equal(request?.url, "http://api.test/internal/agent-tools/delete-task");
  assert.deepEqual(await request?.clone().json(), {
    task_id: "33333333-3333-3333-3333-333333333333",
  });
});

test("create_knowledge is gated by approval unlike the direct-execution tools", async () => {
  const createKnowledge = (await import("../../agent/tools/create_knowledge.ts")).default;

  // 知识条目走「执行前确认」档：内容长、常由模型总结，先看一眼再存。
  assert.notEqual(createKnowledge.approval, undefined);
  assert.equal(createTask.approval, undefined);
});

test("create_knowledge forwards the chosen form's fields", async () => {
  const createKnowledge = (await import("../../agent/tools/create_knowledge.ts")).default;
  const { request } = await withStubbedApi({ record_id: "id", title: "菠菜猪肝汤" }, () =>
    createKnowledge.execute(
      {
        title: "菠菜猪肝汤",
        category: "nutrition",
        form: "recipe",
        ingredients: ["菠菜 200g", "猪肝 100g"],
        steps: ["猪肝切片焯水", "下菠菜煮 3 分钟"],
      },
      scope,
    ),
  );

  assert.equal(request?.url, "http://api.test/internal/agent-tools/create-knowledge");
  const body = (await request?.clone().json()) as Record<string, unknown>;
  assert.equal(body.form, "recipe");
  assert.deepEqual(body.steps, ["猪肝切片焯水", "下菠菜煮 3 分钟"]);
  // 审批过了才会走到 execute，所以这里带 approved 是正确的。
  assert.equal(body.approved, true);
});

test("create_knowledge carries a recipe's purposes", async () => {
  const createKnowledge = (await import("../../agent/tools/create_knowledge.ts")).default;
  const { request } = await withStubbedApi({ record_id: "id", title: "菠菜猪肝汤" }, () =>
    createKnowledge.execute(
      {
        title: "菠菜猪肝汤",
        category: "nutrition",
        form: "recipe",
        ingredients: ["菠菜 200g", "猪肝 100g"],
        steps: ["焯水", "下菠菜"],
        purposes: ["补铁"],
      },
      scope,
    ),
  );

  // 用途是找菜谱的入口，丢了它菜谱就只能靠标题找。
  const body = (await request?.clone().json()) as Record<string, unknown>;
  assert.deepEqual(body.purposes, ["补铁"]);
});

test("create_knowledge allows advice with no verdict", async () => {
  const createKnowledge = (await import("../../agent/tools/create_knowledge.ts")).default;
  const { request } = await withStubbedApi({ record_id: "id", title: "补铁搭配" }, () =>
    createKnowledge.execute(
      {
        title: "补铁搭配",
        category: "nutrition",
        form: "food_rule",
        reason: "补铁的同时吃点维生素C，吸收会好一些",
      },
      scope,
    ),
  );

  // 「补铁要配维C」归不进能吃/不能吃任何一档。
  const body = (await request?.clone().json()) as Record<string, unknown>;
  assert.equal("verdict" in body, false);
  assert.equal(body.reason, "补铁的同时吃点维生素C，吸收会好一些");
});
