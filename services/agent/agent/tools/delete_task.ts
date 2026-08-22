import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 撤销「新建待办」走删除：undo_operation 做的是字段级还原，新建没有可还原的前值。
// 撤销本身就是用户的意思表示，不再要求二次确认。
export default defineTool({
  description:
    "Remove a to-do that was just created, undoing an add. Do not use this to complete " +
    "or cancel a task the user already had — use update_task for those.",
  inputSchema: z.object({ taskId: z.string().uuid() }),
  outputSchema: toolResultSchema,
  async execute({ taskId }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/delete-task", { task_id: taskId });
  },
});
