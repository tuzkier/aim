import { defineAgent, defineDynamic } from "eve";
import { createConfiguredModel } from "./lib/model";
import { resolveAgentModelConfig } from "./lib/model-config";

// 配置错误在进程启动时就暴露，而不是等到第一次对话才失败。
resolveAgentModelConfig();

export default defineAgent({
  description: "Coordinate pregnancy guidance while keeping account and family scope explicit.",
  compaction: { modelContextWindowTokens: 128_000 },
  model: defineDynamic({
    events: {
      "step.started": () => ({
        model: createConfiguredModel(),
        modelContextWindowTokens: 128_000,
      }),
    },
  }),
});
