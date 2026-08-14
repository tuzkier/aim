import { defineAgent, defineDynamic } from "eve";
import { gateModel } from "./lib/model";

export default defineAgent({
  description: "Coordinate pregnancy guidance while keeping account and family scope explicit.",
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
