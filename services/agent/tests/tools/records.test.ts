import assert from "node:assert/strict";
import test from "node:test";
import createRecord from "../../agent/tools/create_record.ts";
import listRecords from "../../agent/tools/list_records.ts";

const scope = {
  session: {
    id: "wrun_records_session",
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
  callId: "call_records_001",
  abortSignal: AbortSignal.timeout(2_000),
} as never;

test("list_records sends only optional record filters in its request body", async () => {
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
        operation_id: "operation_records_001",
        status: "completed",
        summary: "已读取 1 条孕期记录",
        data: { records: [], count: 0 },
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  };

  try {
    const result = await listRecords.execute(
      { type: "symptom", from: "2026-08-01T00:00:00Z", to: "2026-08-16T00:00:00Z" },
      scope,
    );

    assert.equal((result as { status: string }).status, "completed");
    assert.equal(request?.url, "http://api.test/internal/agent-tools/list-records");
    assert.deepEqual(await request?.clone().json(), {
      type: "symptom",
      from: "2026-08-01T00:00:00Z",
      to: "2026-08-16T00:00:00Z",
    });
  } finally {
    globalThis.fetch = previousFetch;
    if (previousSecret === undefined) delete process.env.AGENT_SERVICE_SECRET;
    else process.env.AGENT_SERVICE_SECRET = previousSecret;
    if (previousBaseUrl === undefined) delete process.env.AIM_API_INTERNAL_URL;
    else process.env.AIM_API_INTERNAL_URL = previousBaseUrl;
  }
});

test("AIM can read fetal movement records but cannot create them", () => {
  // 对外类型是通用结构描述，实际是 zod 对象。
  type Schema = { safeParse(value: unknown): { success: boolean } };
  const listSchema = listRecords.inputSchema as unknown as Schema;
  const createSchema = createRecord.inputSchema as unknown as Schema;

  assert.equal(listSchema.safeParse({ type: "fetal_movement" }).success, true);
  // 胎动只能在计数页实时产生，AIM 不得创建。
  assert.equal(createSchema.safeParse({ recordType: "fetal_movement" }).success, false);
});
