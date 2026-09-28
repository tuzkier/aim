import { expect, test } from "vitest";
import { scanTurnWrites, type WriteKind } from "./turnWrites";

const result = (toolName: string, status = "completed") => ({
  type: "action.result",
  data: {
    status: "completed",
    result: { kind: "tool-result", toolName, callId: "c", output: { status } },
  },
});
const end = { type: "session.waiting", data: {} };

test("a turn that wrote a task and a record reports both kinds once", () => {
  const state = { kinds: new Set<WriteKind>() };
  const out = scanTurnWrites(
    [result("create_task"), result("list_tasks"), result("create_record"), end],
    state,
  );
  expect(out).toEqual([["task", "record"]]);
  expect(state.kinds.size).toBe(0);
});

test("read-only turns report nothing", () => {
  expect(scanTurnWrites([result("list_tasks"), end], { kinds: new Set() })).toEqual([]);
});

test("approval_required results are not writes", () => {
  expect(
    scanTurnWrites([result("reschedule_task", "approval_required"), end], { kinds: new Set() }),
  ).toEqual([]);
});

test("kinds accumulate across batches until the turn ends", () => {
  const state = { kinds: new Set<WriteKind>() };
  expect(scanTurnWrites([result("complete_task")], state)).toEqual([]);
  expect(scanTurnWrites([result("create_knowledge"), { type: "turn.completed" }], state)).toEqual([
    ["task", "knowledge"],
  ]);
});

test("undo touches everything it might have reverted", () => {
  expect(scanTurnWrites([result("undo_operation"), end], { kinds: new Set() })).toEqual([
    ["task", "record", "knowledge"],
  ]);
});
