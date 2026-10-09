import assert from "node:assert/strict";
import test from "node:test";
import { localDateTime, toShanghaiIso } from "../agent/lib/local-time.ts";

test("wall-clock time is pinned to Beijing", () => {
  assert.equal(toShanghaiIso("2026-09-29T15:00"), "2026-09-29T15:00:00+08:00");
  assert.equal(toShanghaiIso("2026-09-29T15:00:30"), "2026-09-29T15:00:30+08:00");
});

test("the schema rejects UTC or offset strings so the model cannot shift times by 8 hours", () => {
  assert.equal(localDateTime.safeParse("2026-09-29T15:00").success, true);
  assert.equal(localDateTime.safeParse("2026-09-29T15:00:00Z").success, false);
  assert.equal(localDateTime.safeParse("2026-09-29T15:00:00+08:00").success, false);
  assert.equal(localDateTime.safeParse("明天下午三点").success, false);
});
