import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { createWriteBatcher } from "./writeBatcher";

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

test("38 writes in a burst become one flush with the union of kinds", () => {
  const flush = vi.fn();
  const batcher = createWriteBatcher({ delayMs: 600, maxWaitMs: 2000, flush });
  for (let i = 0; i < 38; i++) batcher.add(i % 2 ? ["task"] : ["task", "record"]);
  expect(flush).not.toHaveBeenCalled();
  vi.advanceTimersByTime(600);
  expect(flush).toHaveBeenCalledTimes(1);
  expect(new Set(flush.mock.calls[0]![0])).toEqual(new Set(["task", "record"]));
});

test("a steady trickle still flushes by the max wait", () => {
  const flush = vi.fn();
  const batcher = createWriteBatcher({ delayMs: 600, maxWaitMs: 2000, flush });
  for (let t = 0; t < 2000; t += 400) {
    batcher.add(["task"]);
    vi.advanceTimersByTime(400);
  }
  expect(flush).toHaveBeenCalledTimes(1);
});

test("nothing added means nothing flushed", () => {
  const flush = vi.fn();
  createWriteBatcher({ delayMs: 600, maxWaitMs: 2000, flush });
  vi.advanceTimersByTime(5000);
  expect(flush).not.toHaveBeenCalled();
});

test("dispose drops a pending flush", () => {
  const flush = vi.fn();
  const batcher = createWriteBatcher({ delayMs: 600, maxWaitMs: 2000, flush });
  batcher.add(["task"]);
  batcher.dispose();
  vi.advanceTimersByTime(5000);
  expect(flush).not.toHaveBeenCalled();
});
