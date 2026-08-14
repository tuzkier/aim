import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description: "Read the current pregnancy context from the Aim business service.",
  inputSchema: z.object({}),
  outputSchema: toolResultSchema,
  async execute(_input, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/get-pregnancy-context");
  },
});
