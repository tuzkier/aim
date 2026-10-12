import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description: "List active baby profiles in the authenticated pregnancy/family. Get baby ids here before logging care; never invent ids.",
  inputSchema: z.object({}),
  outputSchema: toolResultSchema,
  async execute(input, ctx) { return callBusinessApi(ctx, "/internal/agent-tools/list-babies", input); },
});
