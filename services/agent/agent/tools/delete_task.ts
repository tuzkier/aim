import { defineTool } from "eve/tools";
import { always } from "eve/tools/approval";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 「执行前确认」档：待办是硬删除，删了不能撤销。
// 没有这个工具时，模型只能把加错的待办标成完成来「去掉」，留下假的完成记录。
export default defineTool({
  description:
    "Delete a to-do that should not exist: one added by mistake, a duplicate, or one the " +
    "user no longer wants. The user confirms on a card; deletion cannot be undone. " +
    "Never use complete_task to get rid of a wrong to-do — completing means the user did it.",
  inputSchema: z.object({ taskId: z.string().uuid() }),
  outputSchema: toolResultSchema,
  approval: always(),
  async execute({ taskId }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/delete-task", {
      task_id: taskId,
      // Eve 只在确认通过后才调用 execute。
      approved: true,
    });
  },
});
