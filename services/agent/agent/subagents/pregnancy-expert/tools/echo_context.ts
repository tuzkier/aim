import { defineTool } from "eve/tools";
import { z } from "zod";

export default defineTool({
  description: "Return the authenticated scope available to the pregnancy expert.",
  inputSchema: z.object({}),
  async execute(_input, ctx) {
    return {
      accountId: ctx.session.auth.current?.attributes.accountId ?? "",
      familyId: ctx.session.auth.current?.attributes.familyId ?? "",
      pregnancyId: ctx.session.auth.current?.attributes.pregnancyId ?? "",
    };
  },
});
