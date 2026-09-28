import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 「直接执行」档：完成是最常见的一句话操作（「产检做完了」），每次都确认太烦，
// 做错了由 undo_operation 撤回。档位同时在服务端 DIRECT_EXECUTION_TOOLS 声明。
export default defineTool({
  description:
    "Mark one to-do as done when the user says it is finished. Executes immediately; " +
    "tell the user it can be undone. Read list_tasks first to get taskId and version.",
  inputSchema: z.object({
    taskId: z.string().uuid(),
    expectedVersion: z.number().int().min(1),
  }),
  outputSchema: toolResultSchema,
  async execute({ taskId, expectedVersion }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/complete-task", {
      task_id: taskId,
      expected_version: expectedVersion,
    });
  },
});
