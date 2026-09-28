import { expect, test } from "vitest";
import { formatWhen, memberName } from "./bizData";

test("member name prefers nickname, then role", () => {
  expect(memberName({ account_id: "1", role: "father", nickname: "老王", status: "active" })).toBe("老王");
  expect(memberName({ account_id: "1", role: "father", nickname: null, status: "active" })).toBe("爸爸");
  expect(memberName({ account_id: "1", role: "other_caregiver", nickname: " ", status: "active" })).toBe("家人");
  expect(memberName(undefined)).toBe("家人");
});

test("dates render in Chinese month/day with time", () => {
  expect(formatWhen("2026-10-09T01:00:00Z")).toMatch(/10月9日/);
  expect(formatWhen(null)).toBeNull();
  expect(formatWhen("not a date")).toBeNull();
});
