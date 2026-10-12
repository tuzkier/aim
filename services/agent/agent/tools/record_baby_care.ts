import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";
import { localDateTime, toShanghaiIso } from "../lib/local-time.ts";

export default defineTool({
  description: "Record only the feeding, diaper or completed sleep facts explicitly reported by the user. Use list_babies for the baby id; ask which baby if unclear. Do not infer amounts, diagnose, switch life stage or log future events. Family visible unless the user chooses private.",
  inputSchema: z.object({
    babyId: z.string().uuid(),
    kind: z.enum(["feeding", "diaper", "sleep"]),
    occurredAt: localDateTime.optional().describe("Actual start/event time; defaults to now only for an event the user says just happened. Required for sleep."),
    mode: z.enum(["breast", "expressed", "formula", "mixed", "unknown"]).optional(),
    volumeMl: z.number().min(0.1).max(2000).optional().describe("Observed bottle amount only; never estimate breastmilk or unknown amounts."),
    durationMinutes: z.number().int().min(1).max(180).optional(),
    side: z.enum(["left", "right", "both"]).optional(),
    diaperKind: z.enum(["wet", "dirty", "both", "dry"]).optional(),
    endedAt: localDateTime.optional().describe("Required for a completed sleep, later than its start and no later than now."),
    note: z.string().max(500).optional(),
    visibility: z.enum(["family", "private"]).default("family"),
  }),
  outputSchema: toolResultSchema,
  async execute(input, ctx) {
    let data: Record<string, unknown> = { baby_id: input.babyId };
    if (input.kind === "feeding") {
      data = { ...data, mode: input.mode ?? "unknown", volume_ml: input.volumeMl, duration_minutes: input.durationMinutes, side: input.side };
    } else if (input.kind === "diaper") {
      if (!input.diaperKind) throw new Error("请确认尿布是湿、便、都有或干的");
      data.kind = input.diaperKind;
    } else {
      if (!input.occurredAt || !input.endedAt) throw new Error("睡眠需要实际开始与结束时间，不能凭空填时长");
      data.ended_at = toShanghaiIso(input.endedAt);
    }
    return callBusinessApi(ctx, "/internal/agent-tools/create-record", {
      record_type: input.kind, structured_data: data, content: input.note,
      occurred_at: input.occurredAt ? toShanghaiIso(input.occurredAt) : undefined,
      visibility: input.visibility,
      title: input.kind === "feeding" ? "宝宝喂养" : input.kind === "diaper" ? "宝宝尿布" : "宝宝睡眠",
    });
  },
});
