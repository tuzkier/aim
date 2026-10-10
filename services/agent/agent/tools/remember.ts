import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description: "记住用户明确表达、以后仍有用的稳定事实，如偏好、过敏或产检医院。不要记推测、临时状态或用户说不要记的内容。保存后可以撤销。",
  inputSchema: z.object({
    kind: z.enum(["allergy", "history", "medication", "care", "preference", "other"]),
    text: z.string().trim().min(1).max(80).describe("原样保留事实，用一句话表达，不添加医学推断。"),
  }),
  outputSchema: toolResultSchema,
  async execute(input, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/remember", input);
  },
});
