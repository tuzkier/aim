import { defineAgent, defineDynamic } from "eve";
import { createConfiguredModel } from "../../lib/model";

export default defineAgent({
  description: "Provide read-only pregnancy-stage context without changing user data.",
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
