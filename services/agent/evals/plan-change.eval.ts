import { defineEval } from "eve/evals";

export default defineEval({
  description: "A plan mutation pauses for explicit human approval before the business tool executes.",
  async test(t) {
    if (process.env.AIM_RUN_INTEGRATION_EVAL !== "1") {
      t.skip("Requires a running FastAPI service with a seeded pregnancy scope.");
    }

    const response = await t.target.fetch("/eve/v1/session", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-aim-account-id": process.env.AIM_EVAL_ACCOUNT_ID ?? "",
        "x-aim-family-id": process.env.AIM_EVAL_FAMILY_ID ?? "",
        "x-aim-pregnancy-id": process.env.AIM_EVAL_PREGNANCY_ID ?? "",
      },
      body: JSON.stringify({ message: "Please plan a change to my pregnancy task." }),
    });
    if (!response.ok) throw new Error(`plan-change session failed with HTTP ${response.status}`);
    const body = (await response.json()) as { sessionId?: string };
    if (!body.sessionId) throw new Error("plan-change session did not return a session id");

    const session = await t.target.attachSession(body.sessionId);
    session.parked();
    session.calledTool("list_tasks", { count: 1 });
    session.calledTool("preview_task_change", { count: 1 });
    session.requireInputRequest({ toolName: "update_task" });

    const pending = session.requireInputRequest({ toolName: "update_task" });
    const approvedTurn = await session.respond(
      [{ requestId: pending.requestId, optionId: "approve" }],
      {
        headers: {
          "x-aim-account-id": process.env.AIM_EVAL_ACCOUNT_ID ?? "",
          "x-aim-family-id": process.env.AIM_EVAL_FAMILY_ID ?? "",
          "x-aim-pregnancy-id": process.env.AIM_EVAL_PREGNANCY_ID ?? "",
        },
      },
    );
    approvedTurn.succeeded();
    approvedTurn.calledTool("update_task", { status: "completed", count: 1 });
    t.succeeded();
  },
});
