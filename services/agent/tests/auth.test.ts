import assert from "node:assert/strict";
import { afterEach, beforeEach, describe, it } from "node:test";
import { aimSessionAuth } from "../agent/lib/auth.ts";

/**
 * 这个通道经 nginx 直接对公网暴露，所以身份只能从签名过的会话票推导：
 * 票送到业务 API 换取 scope，调用方自报的 `x-aim-*` 头一概不作数。
 *
 * 下面每条用例都对着一种「调用方试图自选身份」的形状。它们看起来啰嗦，
 * 但少任何一条，这层就可能在某次重构里悄悄退回采信调用方。
 */

const ORIGINAL_FETCH = globalThis.fetch;
const ACCOUNT = "11111111-1111-1111-1111-111111111111";
const FAMILY = "22222222-2222-2222-2222-222222222222";
const PREGNANCY = "33333333-3333-3333-3333-333333333333";

type FetchCall = { url: string; init: RequestInit | undefined };

let calls: FetchCall[] = [];

function stubResolveSession(response: { status: number; body?: unknown }): void {
  calls = [];
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    calls.push({ url: String(input), init });
    return new Response(response.body === undefined ? "" : JSON.stringify(response.body), {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }) as typeof globalThis.fetch;
}

function request(headers: Record<string, string>): Request {
  return new Request("http://eve.test/eve/v1/session", { method: "POST", headers });
}

describe("aimSessionAuth", () => {
  beforeEach(() => {
    process.env.AGENT_SERVICE_SECRET = "test-service-secret";
    process.env.AIM_API_INTERNAL_URL = "http://api.test";
    delete process.env.EVE_EVAL_AUTH_TOKEN;
  });

  afterEach(() => {
    globalThis.fetch = ORIGINAL_FETCH;
  });

  it("拒绝自报身份的请求：只有 scope 头、没有 token 时不放行", async () => {
    stubResolveSession({ status: 401 });

    const identity = await aimSessionAuth(
      request({
        "x-aim-account-id": ACCOUNT,
        "x-aim-family-id": FAMILY,
        "x-aim-pregnancy-id": PREGNANCY,
      }),
    );

    assert.equal(identity, null);
  });

  it("拒绝伪造的 token——业务 API 验签不过就没有身份", async () => {
    stubResolveSession({ status: 401 });

    const identity = await aimSessionAuth(
      request({
        authorization: "Bearer aim.v1.forged.deadbeef",
        "x-aim-account-id": ACCOUNT,
        "x-aim-family-id": FAMILY,
        "x-aim-pregnancy-id": PREGNANCY,
      }),
    );

    assert.equal(identity, null);
  });

  it("scope 取自业务 API 的回答，而不是调用方送的头", async () => {
    stubResolveSession({
      status: 200,
      body: { account_id: ACCOUNT, family_id: FAMILY, pregnancy_id: PREGNANCY },
    });

    // 调用方声称自己是另一个家庭——这些值必须被完全忽略。
    const identity = await aimSessionAuth(
      request({
        authorization: "Bearer aim.v1.valid.signature",
        "x-aim-account-id": "99999999-9999-9999-9999-999999999999",
        "x-aim-family-id": "88888888-8888-8888-8888-888888888888",
        "x-aim-pregnancy-id": "77777777-7777-7777-7777-777777777777",
      }),
    );

    assert.ok(identity);
    assert.deepEqual(identity.attributes, {
      accountId: ACCOUNT,
      familyId: FAMILY,
      pregnancyId: PREGNANCY,
    });
    assert.equal(identity.principalId, ACCOUNT);
  });

  it("带着服务凭据去换 scope，并把 token 原样送过去", async () => {
    stubResolveSession({
      status: 200,
      body: { account_id: ACCOUNT, family_id: FAMILY, pregnancy_id: PREGNANCY },
    });

    await aimSessionAuth(request({ authorization: "Bearer aim.v1.valid.signature" }));

    assert.equal(calls.length, 1);
    assert.equal(calls[0]!.url, "http://api.test/internal/agent-tools/resolve-session");
    const headers = new Headers(calls[0]!.init?.headers);
    assert.equal(headers.get("service-authorization"), "Bearer test-service-secret");
    assert.deepEqual(JSON.parse(String(calls[0]!.init?.body)), {
      token: "aim.v1.valid.signature",
    });
  });

  it("业务 API 不可达时不放行——失败要关门，不能退回自报身份", async () => {
    calls = [];
    globalThis.fetch = (async () => {
      throw new Error("connection refused");
    }) as typeof globalThis.fetch;

    const identity = await aimSessionAuth(
      request({ authorization: "Bearer aim.v1.valid.signature" }),
    );

    assert.equal(identity, null);
  });

  it("eval token 那条路仍然走得通", async () => {
    process.env.EVE_EVAL_AUTH_TOKEN = "eval-token";
    stubResolveSession({ status: 401 });

    const identity = await aimSessionAuth(
      request({
        authorization: "Bearer eval-token",
        "x-aim-account-id": ACCOUNT,
        "x-aim-family-id": FAMILY,
        "x-aim-pregnancy-id": PREGNANCY,
      }),
    );

    assert.ok(identity);
    assert.equal(identity.attributes.accountId, ACCOUNT);
    assert.equal(calls.length, 0, "eval 路径不该去打业务 API");
  });
});
