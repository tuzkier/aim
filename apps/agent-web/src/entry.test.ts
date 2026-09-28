import { expect, test } from "vitest";
import { resolveEntry, withPageContext } from "./entry";

const base = { token: "t", theme: "light" as const };

test("missing or malformed entry means resume", () => {
  expect(resolveEntry(base)).toEqual({ mode: "resume" });
  expect(resolveEntry({ ...base, entry: { mode: "weird" } as never })).toEqual({ mode: "resume" });
});

test("new entry keeps page context and auto-send text", () => {
  const entry = {
    mode: "new" as const,
    pageContext: { title: "番茄炒蛋", summary: "菜谱" },
    autoSend: "帮我看看",
  };
  expect(resolveEntry({ ...base, entry })).toEqual(entry);
});

test("blank auto-send is dropped", () => {
  expect(resolveEntry({ ...base, entry: { mode: "new", autoSend: "  " } })).toEqual({ mode: "new" });
});

test("page context rides along as clientContext", () => {
  const input = { message: "能吃吗" };
  expect(withPageContext(input, { title: "番茄炒蛋", summary: "菜谱" })).toEqual({
    message: "能吃吗",
    clientContext: { page: { title: "番茄炒蛋", summary: "菜谱" } },
  });
  expect(withPageContext(input, null)).toBe(input);
});
