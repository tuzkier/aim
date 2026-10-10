import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description: "Read one encyclopedia entry in full by its id (from list_library).",
  inputSchema: z.object({
    id: z.string().regex(/^[a-z]+\.[a-z0-9-]+$/),
  }),
  outputSchema: toolResultSchema,
  async execute(input, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/get-library-entry", input);
  },
});
