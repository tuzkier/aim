import { defineTool } from "eve/tools";
import { always } from "eve/tools/approval";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description: "After the user confirms, record a user-provided pregnancy fact.",
  inputSchema: z.object({
    key: z.string().min(1).max(120),
    value: z.unknown(),
    source: z.enum(["doctor_confirmed", "user_confirmed"]),
  }),
  outputSchema: toolResultSchema,
  approval: always(),
  async execute({ key, value, source }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/record-pregnancy-fact", {
      key,
      value,
      source,
      approved: true,
    });
  },
});
