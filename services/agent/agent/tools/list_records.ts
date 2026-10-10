import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description: "List pregnancy records visible to the authenticated family member.",
  inputSchema: z.object({
    type: z.enum(["symptom", "checkup", "note", "fetal_movement"]).optional(),
    from: z.iso.datetime().optional(),
    to: z.iso.datetime().optional(),
  }),
  outputSchema: toolResultSchema,
  async execute(filters, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/list-records", filters);
  },
});
