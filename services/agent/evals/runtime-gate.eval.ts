import { defineEval } from "eve/evals";

export default defineEval({
  description: "The runtime accepts scoped identity and executes only the declared context tool.",
  async test(t) {
    const response = await t.target.fetch("/eve/v1/session", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-aim-account-id": "eval_account",
        "x-aim-family-id": "eval_family",
        "x-aim-pregnancy-id": "eval_pregnancy",
      },
      body: JSON.stringify({ message: "context" }),
    });
    if (!response.ok) {
      throw new Error(`Runtime gate session creation failed with HTTP ${response.status}.`);
    }

    const body = (await response.json()) as { sessionId?: string };
    if (!body.sessionId) throw new Error("Runtime gate response did not include sessionId.");

    const session = await t.target.attachSession(body.sessionId);
    session.succeeded();
    session.calledTool("echo_context");
    session.notCalledTool("preview_task_change");
    t.succeeded();
  },
});
