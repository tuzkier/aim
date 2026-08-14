import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description: "List the authenticated pregnancy family's current plan tasks.",
  inputSchema: z.object({}),
  outputSchema: toolResultSchema,
  async execute(_input, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/list-tasks");
  },
});
