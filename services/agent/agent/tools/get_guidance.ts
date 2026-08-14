import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description: "Read reviewed pregnancy guidance for a gestational week and region.",
  inputSchema: z.object({
    week: z.number().int().min(0).max(45),
    region: z.string().min(1).max(32).default("CN-ZJ-HZ"),
  }),
  outputSchema: toolResultSchema,
  async execute({ week, region }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/get-guidance", { week, region });
  },
});
