import { defineTool } from "eve/tools";
import { always } from "eve/tools/approval";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description:
    "Assign a to-do to a family member. Use a member_id from get_pregnancy_context.members " +
    "(or null to unassign). The user confirms on a card before it runs.",
  inputSchema: z.object({
    taskId: z.string().uuid(),
    assignedMemberId: z.string().uuid().nullable(),
    expectedVersion: z.number().int().min(1),
  }),
  outputSchema: toolResultSchema,
  approval: always(),
  async execute({ taskId, assignedMemberId, expectedVersion }, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/assign-task", {
      task_id: taskId,
      assigned_member_id: assignedMemberId,
      expected_version: expectedVersion,
      approved: true,
    });
  },
});
