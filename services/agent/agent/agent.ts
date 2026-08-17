import { defineAgent, defineDynamic } from "eve";
import { createConfiguredModel } from "./lib/model";

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
