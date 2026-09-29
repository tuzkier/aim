import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";
import { localDateTime, toShanghaiIso } from "../lib/local-time.ts";

// 「直接执行」档（时间线重设计 §6.1）：建普通待办不打断对话，写入后由客户端
// toast 提供撤销。因此这里不设 approval —— 与 reschedule_task 的 always() 相对。
// 档位同时在服务端的 DIRECT_EXECUTION_TOOLS 里声明，网关不看调用方的 approved 标志。
export default defineTool({
  description:
    "Add one or more to-dos to the pregnancy plan — things the user intends to DO, " +
    "at a point in time: an appointment, an errand, a reminder. " +
    "Use this whenever the user says 待办/提醒/安排/别忘了, even when the wording " +
    "resembles a procedure. This executes immediately and needs no confirmation; " +
    "the user can undo it from the timeline. " +
    "Do NOT use create_knowledge for these — that is for reference material the user " +
    "wants to look up later, and it interrupts them with a confirmation card. " +
    "Call get_current_time before setting dueAt for any relative date.",
  inputSchema: z.object({
    tasks: z
      .array(
        z.object({
          title: z.string().min(1).max(200),
          description: z.string().max(2000).optional(),
          dueAt: localDateTime.optional(),
        }),
      )
      .min(1)
      .max(50)
      .describe("All the to-dos to add, in one call — never one call per to-do."),
  }),
  outputSchema: toolResultSchema,
  async execute({ tasks }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/create-task", {
      tasks: tasks.map(({ title, description, dueAt }) => ({
        title,
        description,
        due_at: dueAt ? toShanghaiIso(dueAt) : undefined,
      })),
    });
  },
});
