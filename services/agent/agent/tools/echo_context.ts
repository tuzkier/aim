import { defineTool } from "eve/tools";
import { z } from "zod";

export default defineTool({
  description: "Return the authenticated Aim account, family, pregnancy, and session scope.",
  inputSchema: z.object({}),
  outputSchema: z.object({
    accountId: z.string(),
    familyId: z.string(),
    pregnancyId: z.string(),
    sessionId: z.string(),
  }),
  async execute(_input, ctx) {
    const auth = ctx.session.auth.current;
    return {
      accountId: auth?.attributes.accountId ?? "",
      familyId: auth?.attributes.familyId ?? "",
      pregnancyId: auth?.attributes.pregnancyId ?? "",
      sessionId: ctx.session.id,
    };
  },
});
