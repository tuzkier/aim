import { defineTool } from "eve/tools";
import { always } from "eve/tools/approval";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description: "用户要求遗忘一条记忆时使用。先读取当前记忆取得真实编号，再显示确认卡。确认后删除，不能撤销；新事实可以另记一条。",
  inputSchema: z.object({
    id: z.string().uuid(),
    text: z.string().max(80).optional().describe("从记忆记录原样取得的一句话，显示给用户核对。"),
  }),
  outputSchema: toolResultSchema,
  approval: always(),
  async execute(input, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/forget-memory", { id: input.id, approved: true });
  },
});
