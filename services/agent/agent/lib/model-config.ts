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
    model: env.AIM_AGENT_MODEL?.trim() || "deepseek-chat",
  };
}
