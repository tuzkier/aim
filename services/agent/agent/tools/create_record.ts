import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 「直接执行」档，同 create_task。
// note 类型要求 content 非空，symptom / checkup 走 structuredData —— 这是后端领域规则。
export default defineTool({
  description:
    "Record something for the family: a note, a symptom, or a checkup result. " +
    "Use this when the user wants to write something down or remember how they felt.",
  inputSchema: z.object({
    recordType: z.enum(["symptom", "checkup", "note"]),
    content: z.string().max(4000).optional(),
    title: z.string().max(200).optional(),
    structuredData: z.record(z.string(), z.unknown()).optional(),
    occurredAt: z.iso.datetime().optional(),
  }),
  outputSchema: toolResultSchema,
  async execute({ recordType, content, title, structuredData, occurredAt }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/create-record", {
      record_type: recordType,
      content,
      title,
      structured_data: structuredData,
      occurred_at: occurredAt,
    });
  },
});
