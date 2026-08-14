import { defineAgent, defineDynamic } from "eve";
import { gateModel } from "../../lib/model";

export default defineAgent({
  description: "Provide read-only pregnancy-stage context without changing user data.",
  compaction: { modelContextWindowTokens: 128_000 },
  model: defineDynamic({
    events: {
      "step.started": () => ({
        model: process.env.EVE_USE_MOCK_MODEL === "1" ? gateModel : "zai/glm-5.2",
        modelContextWindowTokens: 128_000,
      }),
    },
  }),
});
