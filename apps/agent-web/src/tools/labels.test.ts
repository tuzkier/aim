import { expect, test } from "vitest";
import { approvalCopy, toolTitle } from "./labels";

test("each gated tool gets its own verbs", () => {
  expect(approvalCopy(["reschedule_task"]).confirm).toBe("确认改期");
  expect(approvalCopy(["assign_task"]).confirm).toBe("确认指派");
  expect(approvalCopy(["record_pregnancy_fact"]).confirm).toBe("确认更新");
  expect(approvalCopy(["create_knowledge"]).confirm).toBe("收录");
  expect(approvalCopy(["delete_task"]).confirm).toBe("确认删除");
  expect(approvalCopy(["delete_task"]).reject).toBe("保留");
});

test("mixed batches fall back to neutral wording", () => {
  const copy = approvalCopy(["reschedule_task", "assign_task"]);
  expect(copy.confirm).toBe("确认");
  expect(copy.reject).toBe("取消");
});

test("nothing says 收录 unless the batch is only knowledge", () => {
  for (const name of ["reschedule_task", "assign_task", "delete_task", "record_pregnancy_fact", "unknown_tool"]) {
    const copy = approvalCopy([name]);
    expect(Object.values(copy).join("")).not.toContain("收录");
  }
});

test("the checkup report tool has a Chinese step title", () => {
  expect(toolTitle("create_checkup_report")).toBe("记一份产检报告");
});

test("the checkup report approval speaks of saving the report", () => {
  const copy = approvalCopy(["create_checkup_report"]);
  expect(copy.confirm).toBe("记下");
  expect(copy.reject).toBe("先不记");
  expect(copy.rejected).toBe("没有记下");
});
