import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 撤销「新建记录」。走记录自身的软删除。
export default defineTool({
  description: "Remove a record that was just created, undoing it.",
  inputSchema: z.object({ recordId: z.string().uuid() }),
  outputSchema: toolResultSchema,
  async execute({ recordId }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/delete-record", { record_id: recordId });
  },
});
