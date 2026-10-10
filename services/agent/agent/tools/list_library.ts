import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description:
    "List the pregnancy encyclopedia catalog (titles, aliases, weeks, one-line summaries; no full text). " +
    "Defaults to entries relevant to the user's current week; pass topic to browse one topic " +
    "(checkup, body, diet, life, birth, paperwork).",
  inputSchema: z.object({
    topic: z.enum(["checkup", "body", "diet", "life", "birth", "paperwork"]).optional(),
    week: z.number().int().min(0).max(45).optional(),
  }),
  outputSchema: toolResultSchema,
  async execute(input, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/list-library", input);
  },
});
