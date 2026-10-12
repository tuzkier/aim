import assert from "node:assert/strict";
import test from "node:test";
import babyCare from "../../agent/tools/record_baby_care.ts";
import listBabies from "../../agent/tools/list_babies.ts";

const ctx = { session: { id: "baby-test", auth: { current: { attributes: {
  accountId: "account-test", familyId: "family-test", pregnancyId: "pregnancy-test",
} } } }, callId: "care-test", abortSignal: AbortSignal.timeout(2000) } as never;

test("baby care keeps observed amount and private visibility, and requires actual sleep times", async () => {
  const previousFetch = globalThis.fetch;
  const previousSecret = process.env.AGENT_SERVICE_SECRET;
  const previousUrl = process.env.AIM_API_INTERNAL_URL;
  process.env.AGENT_SERVICE_SECRET = "test"; process.env.AIM_API_INTERNAL_URL = "http://api.test";
  let request: Request | undefined;
  globalThis.fetch = async (url, init) => {
    request = new Request(url, init);
    return new Response(JSON.stringify({ operation_id: "care-1", status: "completed", summary: "已记录", data: {} }), { headers: { "content-type": "application/json" } });
  };
  try {
    const id = "a1111111-1111-4111-8111-111111111111";
    await babyCare.execute({ babyId: id, kind: "feeding", mode: "formula", volumeMl: 60.5, visibility: "private" }, ctx);
    assert.equal(request?.url, "http://api.test/internal/agent-tools/create-record");
    const body = await request!.clone().json();
    assert.equal(body.visibility, "private"); assert.equal(body.structured_data.volume_ml, 60.5); assert.equal(body.structured_data.baby_id, id);
    await assert.rejects(async () => await babyCare.execute({ babyId: id, kind: "sleep", visibility: "family" }, ctx), /实际开始/);
    await listBabies.execute({}, ctx);
    assert.equal(request?.url, "http://api.test/internal/agent-tools/list-babies");
  } finally {
    globalThis.fetch = previousFetch;
    if (previousSecret === undefined) delete process.env.AGENT_SERVICE_SECRET; else process.env.AGENT_SERVICE_SECRET = previousSecret;
    if (previousUrl === undefined) delete process.env.AIM_API_INTERNAL_URL; else process.env.AIM_API_INTERNAL_URL = previousUrl;
  }
});
