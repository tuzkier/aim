import { defineTool } from "eve/tools";
import { always } from "eve/tools/approval";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 「执行前确认」档：待办是硬删除，删了不能撤销。
// 没有这个工具时，模型只能把加错的待办标成完成来「去掉」，留下假的完成记录。
export default defineTool({
  description:
    "Delete to-dos that should not exist: added by mistake, duplicates, or no longer wanted. " +
    "Pass all of them in one call — the user confirms the whole batch on one card, and " +
    "deletion cannot be undone. Never use complete_task to get rid of a wrong to-do — " +
    "completing means the user did it.",
  inputSchema: z.object({ taskIds: z.array(z.string().uuid()).min(1).max(50) }),
  outputSchema: toolResultSchema,
  approval: always(),
  async execute({ taskIds }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/delete-task", {
      task_ids: taskIds,
      // Eve 只在确认通过后才调用 execute。
      approved: true,
    });
  },
});
