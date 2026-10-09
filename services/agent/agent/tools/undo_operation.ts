import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 撤销本身就是用户的明确意思，不再二次确认。
export default defineTool({
  description:
    "Undo something you did earlier in this conversation. Pass the operationId from that " +
    "tool's result. Works for created to-dos and records, completed or rescheduled to-dos, " +
    "and assignments. Pregnancy facts cannot be undone.",
  inputSchema: z.object({ operationId: z.string().uuid() }),
  outputSchema: toolResultSchema,
  async execute({ operationId }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/undo-operation", {
      operation_id: operationId,
    });
  },
});
