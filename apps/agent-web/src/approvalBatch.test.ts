import { describe, expect, test } from "vitest";
import { nextDispatch } from "./approvalBatch";

const d = (approved: boolean) => ({ approved });

describe("nextDispatch", () => {
  test("waits until every pending approval has a decision", () => {
    expect(nextDispatch(["a", "b"], new Map([["a", d(true)]]), new Set())).toBeNull();
  });

  test("sends the whole batch once all are decided", () => {
    const result = nextDispatch(["b", "a"], new Map([["a", d(true)], ["b", d(false)]]), new Set());
    expect(result).toEqual({
      key: "a|b",
      payload: [
        { requestId: "b", approved: false },
        { requestId: "a", approved: true },
      ],
    });
  });

  test("does not resend a batch already dispatched", () => {
    expect(nextDispatch(["a"], new Map([["a", d(true)]]), new Set(["a"]))).toBeNull();
  });

  test("nothing pending means nothing to send", () => {
    expect(nextDispatch([], new Map(), new Set())).toBeNull();
  });
});
