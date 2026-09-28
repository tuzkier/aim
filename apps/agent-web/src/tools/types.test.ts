import { expect, test } from "vitest";
import { pendingApprovalTools } from "./types";

test("only tool calls still awaiting a decision count", () => {
  const parts = [
    { type: "text", text: "好的" },
    { type: "tool-call", toolName: "reschedule_task", approval: { id: "1" } },
    { type: "tool-call", toolName: "assign_task", approval: { id: "2", approved: true } },
    { type: "tool-call", toolName: "create_knowledge", approval: { id: "3", resolution: "expired" } },
    { type: "tool-call", toolName: "list_tasks" },
  ];
  expect(pendingApprovalTools(parts)).toEqual(["reschedule_task"]);
});
