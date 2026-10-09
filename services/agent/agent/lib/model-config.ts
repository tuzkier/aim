export type AgentModelConfig =
  | { kind: "mock" }
  | {
      kind: "deepseek";
      apiKey: string;
      baseURL: string;
      model: string;
    };

type Environment = Record<string, string | undefined>;

export function resolveAgentModelConfig(env: Environment = process.env): AgentModelConfig {
  if (env.EVE_USE_MOCK_MODEL !== "0") {
    // 线上漏配一个变量就退回 mock，用户会收到一句英文的 "runtime is ready"。
    // 宁可起不来，也不要看起来正常。
    if (env.AIM_DEPLOYMENT === "production") {
      throw new Error(
        "AIM_DEPLOYMENT=production requires EVE_USE_MOCK_MODEL=0 and DEEPSEEK_API_KEY",
      );
    }
    return { kind: "mock" };
  }

  const apiKey = env.DEEPSEEK_API_KEY?.trim();
  if (!apiKey) {
    throw new Error("DEEPSEEK_API_KEY is required when EVE_USE_MOCK_MODEL=0");
  }

  return {
    kind: "deepseek",
    apiKey,
    baseURL: (env.DEEPSEEK_BASE_URL?.trim() || "https://api.deepseek.com").replace(/\/$/, ""),
    // deepseek-flash 能读图；AIM 的图片功能依赖这一点。
    model: env.AIM_AGENT_MODEL?.trim() || "deepseek-flash",
  };
}
