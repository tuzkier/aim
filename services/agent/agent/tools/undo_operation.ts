import { defineTool } from "eve/tools";
import { always } from "eve/tools/approval";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description: "After the user confirms, undo a previously recorded task change.",
  inputSchema: z.object({
    changeId: z.string().uuid(),
    expectedVersion: z.number().int().min(1),
  }),
  outputSchema: toolResultSchema,
  approval: always(),
  async execute({ changeId, expectedVersion }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/undo-operation", {
      change_id: changeId,
      expected_version: expectedVersion,
      approved: true,
    });
  },
});
