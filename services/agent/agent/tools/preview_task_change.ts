import { defineTool } from "eve/tools";
import { z } from "zod";

export default defineTool({
  description: "Create a non-mutating preview of a task change for the authenticated pregnancy.",
  inputSchema: z.object({
    taskId: z.string().min(1),
    action: z.enum(["complete", "snooze", "assign"]),
  }),
  outputSchema: z.object({
    status: z.literal("preview"),
    taskId: z.string(),
    action: z.enum(["complete", "snooze", "assign"]),
    pregnancyId: z.string(),
  }),
  async execute({ taskId, action }, ctx) {
    return {
      action,
      pregnancyId: ctx.session.auth.current?.attributes.pregnancyId ?? "",
      status: "preview" as const,
      taskId,
    };
  },
});
