import { z } from "zod";

export const toolResultSchema = z.object({
  operationId: z.string(),
  status: z.enum(["completed", "approval_required"]),
  summary: z.string(),
  data: z.record(z.string(), z.unknown()),
});
