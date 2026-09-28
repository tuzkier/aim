import { defineTool } from "eve/tools";
import { always } from "eve/tools/approval";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description:
    "Change when a to-do happens. kind=schedule sets a concrete time the user will do it " +
    "(e.g. a booked checkup); kind=delay only pushes the deadline later. " +
    "The user confirms on a card before it runs.",
  inputSchema: z.object({
    taskId: z.string().uuid(),
    expectedVersion: z.number().int().min(1),
    kind: z.enum(["schedule", "delay"]),
    at: z.string().datetime(),
  }),
  outputSchema: toolResultSchema,
  approval: always(),
  async execute({ taskId, expectedVersion, kind, at }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/reschedule-task", {
      task_id: taskId,
      expected_version: expectedVersion,
      kind,
      at,
      // Eve 只在确认通过后才调用 execute。
      approved: true,
    });
  },
});
