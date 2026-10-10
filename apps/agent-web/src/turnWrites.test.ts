import { expect, test } from "vitest";
import { writesIn } from "./turnWrites";

const result = (toolName: string, status = "completed") => ({
  type: "action.result",
  data: {
    status: "completed",
    result: { kind: "tool-result", toolName, callId: "c", output: { status } },
  },
});

test("a batch with a task and a record write reports both kinds once", () => {
  expect(writesIn([result("create_task"), result("list_tasks"), result("create_record")])).toEqual([
    "task",
    "record",
  ]);
});

test("reports as soon as the write result arrives, without waiting for the turn to end", () => {
  // 用户看到「已添加」就会切回首页，那时模型可能还在写收尾的话。
  expect(writesIn([result("complete_task")])).toEqual(["task"]);
});

test("read-only batches report nothing", () => {
  expect(writesIn([result("list_tasks"), { type: "session.waiting" }])).toEqual([]);
});

test("approval_required results are not writes", () => {
  expect(writesIn([result("reschedule_task", "approval_required")])).toEqual([]);
});

test("undo touches everything it might have reverted", () => {
  expect(writesIn([result("undo_operation")])).toEqual(["task", "record", "knowledge"]);
});

test("deleting a to-do refreshes the task pages", () => {
  expect(writesIn([result("delete_task")])).toEqual(["task"]);
});

test("a saved checkup report refreshes the records pages", () => {
  // 报告和随它攒下的「想问医生」都是记录，资料库要跟着刷新。
  expect(writesIn([result("create_checkup_report")])).toEqual(["record"]);
});
