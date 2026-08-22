import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 「直接执行」档（时间线重设计 §6.1）：建普通待办不打断对话，写入后由客户端
// toast 提供撤销。因此这里不设 approval —— 与 update_task 的 always() 相对。
// 档位同时在服务端的 DIRECT_EXECUTION_TOOLS 里声明，网关不看调用方的 approved 标志。
export default defineTool({
  description:
    "Add a new to-do to the pregnancy plan. Use this when the user asks to remember, " +
    "plan, or schedule something. The task appears on the timeline marked as agent-created " +
    "and the user can undo it.",
  inputSchema: z.object({
    title: z.string().min(1).max(200),
    description: z.string().max(2000).optional(),
    dueAt: z.iso.datetime().optional(),
  }),
  outputSchema: toolResultSchema,
  async execute({ title, description, dueAt }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/create-task", {
      title,
      description,
      due_at: dueAt,
    });
  },
});
