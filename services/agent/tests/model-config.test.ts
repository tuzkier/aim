import assert from "node:assert/strict";
import test from "node:test";
import { resolveAgentModelConfig } from "../agent/lib/model-config.ts";

test("mock mode wins when it is explicitly enabled", () => {
  const config = resolveAgentModelConfig({
    EVE_USE_MOCK_MODEL: "1",
    DEEPSEEK_API_KEY: "test-key",
  });

  assert.deepEqual(config, { kind: "mock" });
});

test("deepseek mode uses the server-side OpenAI-compatible settings", () => {
  const config = resolveAgentModelConfig({
    EVE_USE_MOCK_MODEL: "0",
    DEEPSEEK_API_KEY: "test-key",
    DEEPSEEK_BASE_URL: "https://api.deepseek.com",
    AIM_AGENT_MODEL: "deepseek-chat",
  });

  assert.deepEqual(config, {
    kind: "deepseek",
    apiKey: "test-key",
    baseURL: "https://api.deepseek.com",
    model: "deepseek-chat",
  });
});

test("live mode fails early when the DeepSeek key is missing", () => {
  assert.throws(
    () =>
      resolveAgentModelConfig({
        EVE_USE_MOCK_MODEL: "0",
        DEEPSEEK_BASE_URL: "https://api.deepseek.com",
      }),
    /DEEPSEEK_API_KEY/,
  );
});
