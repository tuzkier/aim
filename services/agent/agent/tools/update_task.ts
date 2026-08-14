import { defineTool } from "eve/tools";
import { always } from "eve/tools/approval";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

const inputSchema = z.object({
  taskId: z.string().uuid(),
  action: z.enum(["schedule", "complete", "delay"]),
  expectedVersion: z.number().int().min(1),
  scheduledFor: z.string().datetime().optional(),
  dueAt: z.string().datetime().optional(),
});

export default defineTool({
  description: "After the user confirms, update one task in the pregnancy plan.",
  inputSchema,
  outputSchema: toolResultSchema,
  approval: always(),
  async execute({ taskId, action, expectedVersion, scheduledFor, dueAt }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/update-task", {
      task_id: taskId,
      action,
      expected_version: expectedVersion,
      scheduled_for: scheduledFor,
      due_at: dueAt,
      // Eve only invokes execute after its durable approval request is accepted.
      approved: true,
    });
  },
});
