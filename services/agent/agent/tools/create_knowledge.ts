import { defineTool } from "eve/tools";
import { always } from "eve/tools/approval";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 「执行前确认」档：知识条目内容长，且常是模型总结出来的，先让用户看一眼再存。
// 与 create_task / create_record 的直接执行档相对。
export default defineTool({
  description:
    "Save reference material to the user's library — something they will look up " +
    "later, not something they intend to do. Recipes, whether a food is safe, how a " +
    "procedure works. " +
    "If the user is asking to remember, schedule or be reminded of an action, that is " +
    "a to-do: use create_task instead. It runs without interrupting them, while this " +
    "tool always asks for confirmation first. When in doubt between the two, prefer " +
    "create_task — an unwanted to-do is one tap to undo, an unwanted confirmation card " +
    "blocks the conversation. " +
    "Use form=recipe for dishes — always fill purposes with what the dish is good for " +
    "(e.g. 补铁, 缓解孕吐, 补钙), that is how the user finds it later. " +
    "Use form=food_rule for anything about how to eat: whether something is safe " +
    "(set verdict), or advice with no yes/no answer such as pairing or meal timing " +
    "(leave verdict out, reason carries the advice). Use form=howto for procedures with steps, " +
    "and form=tip for a short standalone note. Fill every field the chosen form needs — " +
    "a recipe without steps is not worth saving.",
  inputSchema: z.object({
    title: z.string().min(1).max(200),
    category: z.enum([
      "nutrition",
      "paperwork",
      "preparation",
      "checkups",
      "symptoms",
      "questions",
    ]),
    form: z.enum(["recipe", "food_rule", "howto", "tip"]),
    ingredients: z.array(z.string().min(1)).optional(),
    steps: z.array(z.string().min(1)).optional(),
    // 用途是找菜谱的入口——孕期找菜的起点几乎总是「我缺铁，吃什么」。
    purposes: z.array(z.string().min(1)).max(4).optional(),
    // 三档而不是能/不能两档：孕期饮食大量情况是「可以但要限量」。
    verdict: z.enum(["safe", "limit", "avoid"]).optional(),
    reason: z.string().max(2000).optional(),
    body: z.string().max(4000).optional(),
    note: z.string().max(2000).optional(),
  }),
  outputSchema: toolResultSchema,
  approval: always(),
  async execute(input, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/create-knowledge", {
      ...input,
      // Eve 只在自己的持久化审批被接受后才调用 execute。
      approved: true,
    });
  },
});
