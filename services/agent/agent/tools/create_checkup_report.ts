import { defineTool } from "eve/tools";
import { always } from "eve/tools/approval";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

// 「执行前确认」档：报告单上的数字是模型读出来的，存之前让用户在卡片上核对一遍。
// 一次调用建一条产检报告，外加从异常项攒出来的「想问医生」；撤销时整批一起撤。
//
// 指标用逐键可选的严格对象而不是 z.record：效果一样（只认这几个键），
// 但生成的 JSON Schema 不带 propertyNames，OpenAI 兼容的函数调用都认。
const metrics = z
  .strictObject({
    weight_kg: z.number().optional(),
    systolic: z.number().optional(),
    diastolic: z.number().optional(),
    fasting_glucose: z.number().optional(),
    hemoglobin: z.number().optional(),
    fetal_heart_rate: z.number().optional(),
    fundal_height_cm: z.number().optional(),
  })
  .describe(
    "Units: weight_kg kg, systolic/diastolic mmHg, fasting_glucose mmol/L, " +
      "hemoglobin g/L, fetal_heart_rate bpm, fundal_height_cm cm.",
  );

const otherItem = z.object({
  name: z
    .string()
    .min(1)
    .max(40)
    .describe("The item's name as printed, e.g. 尿蛋白."),
  value: z
    .string()
    .min(1)
    .max(40)
    .describe("The value as printed, e.g. + or 11.2."),
  unit: z.string().max(20).optional(),
  reference: z
    .string()
    .max(60)
    .optional()
    .describe("The reference range as printed."),
  flag: z
    .enum(["high", "low", "abnormal"])
    .optional()
    .describe(
      "Only from an arrow or mark on the report, or a value clearly " +
        "outside the printed reference range. Leave out otherwise.",
    ),
});

export default defineTool({
  description:
    "Save a prenatal checkup report the user sent a photo of: one " +
    "checkup record with what you read, plus follow-up questions for " +
    "the doctor. Use this instead of create_record for checkup report " +
    "photos. Fill only what you can read clearly — never guess a blurry " +
    "value. Put the standard measurements in metrics and every other " +
    "test line in otherItems. Turn flagged items into short questions " +
    "for the doctor (at most 5), not conclusions. The user confirms on " +
    "a card before anything is saved; it can be undone as a whole.",
  inputSchema: z.object({
    date: z.iso
      .date()
      .describe("The report date printed on the sheet, YYYY-MM-DD."),
    hospital: z.string().max(100).optional(),
    metrics: metrics.optional(),
    otherItems: z.array(otherItem).max(60).optional(),
    result: z
      .string()
      .max(500)
      .optional()
      .describe("The report's own conclusion, if printed."),
    doctorAdvice: z
      .string()
      .max(500)
      .optional()
      .describe("The doctor's advice, if written."),
    followUpQuestions: z
      .array(z.string().min(1).max(60))
      .max(5)
      .optional()
      .describe(
        "Questions to ask the doctor next time, one short sentence each.",
      ),
    attachmentIds: z
      .array(z.string().uuid())
      .max(4)
      .optional()
      .describe(
        "Ids of the report photos, from the photo list in your context.",
      ),
  }),
  outputSchema: toolResultSchema,
  approval: always(),
  async execute(input, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/create-checkup-report", {
      date: input.date,
      hospital: input.hospital,
      metrics: input.metrics,
      other_items: input.otherItems,
      attachment_ids: input.attachmentIds?.length
        ? input.attachmentIds
        : undefined,
      result: input.result,
      doctor_advice: input.doctorAdvice,
      follow_up_questions: input.followUpQuestions,
      // Eve 只在自己的持久化审批被接受后才调用 execute。
      approved: true,
    });
  },
});
