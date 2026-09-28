import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 「直接执行」档，同 create_task。
//
// 字段平铺而不是用判别联合：OpenAI 兼容的函数调用要求顶层是 object，
// 顶层 anyOf 会被部分提供方拒收。按类型该填哪些，写在各字段的 describe 里，
// 缺了在这里先拦下，错误信息回到模型手里让它补。
const metrics = z
  .object({
    weight_kg: z.number().optional(),
    systolic: z.number().optional(),
    diastolic: z.number().optional(),
    fasting_glucose: z.number().optional(),
    hemoglobin: z.number().optional(),
  })
  .describe("checkup only. Units: kg, mmHg, mmol/L, g/L.");

type RecordInput = {
  recordType: "symptom" | "checkup" | "note";
  symptoms?: string[];
  severity?: number;
  symptomNote?: string;
  hospital?: string;
  examItems?: string;
  result?: string;
  doctorAdvice?: string;
  metrics?: Record<string, number | undefined>;
};

function structuredDataFor(input: RecordInput): Record<string, unknown> {
  if (input.recordType === "symptom") {
    if (!input.symptoms?.length) throw new Error("症状记录至少写一个症状（symptoms）");
    if (input.severity === undefined) throw new Error("症状记录需要严重程度 severity（1–5）");
    return {
      symptoms: input.symptoms,
      severity: input.severity,
      ...(input.symptomNote ? { note: input.symptomNote } : {}),
    };
  }
  if (input.recordType === "checkup") {
    // 后端要求这四项都是字符串（可以为空），指标名只能取固定的几种。
    const cleanMetrics = Object.fromEntries(
      Object.entries(input.metrics ?? {}).filter(([, value]) => value !== undefined),
    );
    return {
      hospital: input.hospital ?? "",
      exam_items: input.examItems ?? "",
      result: input.result ?? "",
      doctor_advice: input.doctorAdvice ?? "",
      ...(Object.keys(cleanMetrics).length ? { metrics: cleanMetrics } : {}),
    };
  }
  return {};
}

export default defineTool({
  description:
    "Record something for the family: a note, a symptom, or a checkup result. " +
    "Use this when the user wants to write something down or remember how they felt.",
  inputSchema: z.object({
    recordType: z.enum(["symptom", "checkup", "note"]),
    title: z.string().max(200).optional(),
    content: z.string().max(4000).optional().describe("note only: the text to keep."),
    symptoms: z.array(z.string().min(1)).optional().describe("symptom only: at least one."),
    severity: z
      .number()
      .int()
      .min(1)
      .max(5)
      .optional()
      .describe("symptom only: 1 mild … 5 severe."),
    symptomNote: z.string().max(1000).optional().describe("symptom only: extra detail."),
    hospital: z.string().optional().describe("checkup only."),
    examItems: z.string().optional().describe("checkup only: what was examined."),
    result: z.string().optional().describe("checkup only: the findings."),
    doctorAdvice: z.string().optional().describe("checkup only."),
    metrics: metrics.optional(),
    occurredAt: z.iso.datetime().optional(),
  }),
  outputSchema: toolResultSchema,
  async execute(input, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/create-record", {
      record_type: input.recordType,
      title: input.title,
      content: input.recordType === "note" ? input.content : undefined,
      structured_data: structuredDataFor(input),
      occurred_at: input.occurredAt,
    });
  },
});
