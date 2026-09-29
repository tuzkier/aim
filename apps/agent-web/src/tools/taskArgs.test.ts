import { expect, test } from "vitest";
import { askQuestionView, deleteTaskIds, taskDrafts } from "./taskArgs";

test("batch create args list every draft", () => {
  expect(taskDrafts({ tasks: [{ title: "买奶瓶" }, { title: "买湿巾", dueAt: "2026-10-01T10:00" }] })).toEqual([
    { title: "买奶瓶" },
    { title: "买湿巾", dueAt: "2026-10-01T10:00" },
  ]);
});

test("old single-task args from past conversations still render", () => {
  expect(taskDrafts({ title: "拿报告", description: "带上医保卡", dueAt: "2026-09-29T15:00" })).toEqual([
    { title: "拿报告", description: "带上医保卡", dueAt: "2026-09-29T15:00" },
  ]);
  expect(taskDrafts(undefined)).toEqual([]);
});

test("delete ids come from the batch or the old single field", () => {
  expect(deleteTaskIds({ taskIds: ["a", "b"] })).toEqual(["a", "b"]);
  expect(deleteTaskIds({ taskId: "a" })).toEqual(["a"]);
  expect(deleteTaskIds({})).toEqual([]);
});

test("old ask_question cards show the question and options in Chinese form", () => {
  expect(
    askQuestionView({ question: "删哪一条？", options: [{ label: "买奶瓶" }, { label: "买奶瓶刷" }] }),
  ).toEqual({ question: "删哪一条？", options: ["买奶瓶", "买奶瓶刷"] });
  expect(askQuestionView({ prompt: "要现在删吗", options: ["是", "否"] })).toEqual({
    question: "要现在删吗",
    options: ["是", "否"],
  });
  expect(askQuestionView(undefined)).toEqual({ question: null, options: [] });
});
