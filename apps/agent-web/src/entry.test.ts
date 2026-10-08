import { expect, test } from "vitest";
import { resolveEntry, withTurnContext } from "./entry";

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
  expect(withTurnContext(input, { page: { title: "番茄炒蛋", summary: "菜谱" }, images: null })).toEqual({
    message: "能吃吗",
    clientContext: { page: { title: "番茄炒蛋", summary: "菜谱" } },
  });
  expect(withTurnContext(input, { page: null, images: null })).toBe(input);
  expect(withTurnContext(input, { page: { title: "番茄炒蛋", summary: "菜谱" }, images: "photos" })).toEqual({
    message: "能吃吗",
    clientContext: { page: { title: "番茄炒蛋", summary: "菜谱" }, images: "photos" },
  });
});

test("a photo from the home page rides along only if it is an image", () => {
  const photo = "data:image/jpeg;base64,/9j/";
  expect(resolveEntry({ ...base, entry: { mode: "new", attachImage: photo } })).toEqual({
    mode: "new",
    attachImage: photo,
  });
  expect(resolveEntry({ ...base, entry: { mode: "new", attachImage: "javascript:alert(1)" } })).toEqual({
    mode: "new",
  });
});
