import { expect, test } from "vitest";
import { memoryHeadline, memoryOperationID } from "./memoryState";

test("成功之前不显示已记住，也不提供撤销编号", () => {
  expect(memoryHeadline(undefined)).toBe("正在记住");
  expect(memoryHeadline(undefined, true)).toBe("没有记住");
  expect(memoryHeadline({ status: "completed" })).toBe("已记住");
  expect(memoryOperationID({ status: "approval_required", operation_id: "a" })).toBeUndefined();
  expect(memoryOperationID({ status: "completed", operationId: "b" })).toBe("b");
});
