import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

// 急症清单此前在指令里写了两份、内容不一致：读不到 red_flags 或孕周不在窗口时，
// 破水、腹痛等可能被降档。这里锁住「只有一份清单、两处都引用它」。
const instructions = await readFile(
  new URL("../agent/instructions.md", import.meta.url),
  "utf8",
);

const LIST_START = "These are emergencies:";

function emergencyList(): string {
  const start = instructions.indexOf(LIST_START);
  assert.ok(start >= 0, "指令里要有一份急症清单");
  const end = instructions.indexOf("\n\n", start);
  return instructions.slice(start, end).replace(/\s+/g, " ");
}

test("急症清单只有一份，并且是两处原清单的并集", () => {
  assert.equal(instructions.split(LIST_START).length, 2);
  const list = emergencyList();
  for (const sign of [
    "heavy bleeding",
    "any vaginal bleeding after 20 weeks",
    "severe belly pain",
    "regular tightening or pressure before 37 weeks",
    "a seizure",
    "confusion or fainting",
    "chest pain or shortness of breath",
    "waters breaking or fluid that keeps leaking",
    "the baby moving clearly less or not at all",
    "a severe headache, blurred vision or constant upper-right belly pain",
    "blood pressure of 160 systolic or 110 diastolic or higher",
    "a temperature of 38.5℃ or higher",
    "one calf swollen and painful",
    "thoughts of harming oneself or the baby",
  ]) {
    assert.ok(list.includes(sign), sign);
  }
  // 急症的具体症状只在清单里列一次，别处不再各写一份。
  assert.equal(instructions.match(/seizure/g)?.length, 1);
});

test("第一句劝就医与兜底都引用这份清单", () => {
  const flat = instructions.replace(/\s+/g, " ");
  assert.ok(flat.includes("sounds like anything on the emergency list above"));
  assert.ok(flat.includes("anything on the emergency list above always means seeking care now"));
});

test("急症段落每行不超过 80 列", () => {
  const start = instructions.indexOf(LIST_START);
  const end = instructions.indexOf("`get_pregnancy_context` returns `red_flags`");
  const long = instructions
    .slice(start, end)
    .split("\n")
    .filter((line) => [...line].length > 80);
  assert.deepEqual(long, []);
});

// 资料段：知识问答先翻资料、回答里引用；但症状匹配急症时就医那句必须先于翻资料。
const LIBRARY_START = "For pregnancy knowledge questions";

function libraryParagraph(): string {
  const start = instructions.indexOf(LIBRARY_START);
  assert.ok(start >= 0, "指令里要有资料段");
  const end = instructions.indexOf("\n\n", start);
  return instructions.slice(start, end).replace(/\s+/g, " ");
}

test("只引用工具或页面上下文给出的编号，百科条目读过才引用", () => {
  // 资料页、记录详情问 AIM 时，上下文里给了记录编号；旧规则「只能引用工具返回的」与之矛盾。
  const paragraph = libraryParagraph();
  assert.ok(
    paragraph.includes(
      "Only cite ids that a tool returned in this conversation or that the current " +
        "page context gives you; never invent one.",
    ),
  );
  assert.ok(paragraph.includes("Cite an encyclopedia entry only after reading it with get_library_entry."));
  assert.ok(!paragraph.includes("Only cite ids that a tool returned in this conversation;"), "旧规则与页面上下文矛盾");
});

test("症状匹配急症时，先写就医那句再翻资料，这一轮可以不翻", () => {
  assert.ok(
    libraryParagraph().includes(
      "If the symptom matches an urgent red flag, write that seek-care sentence " +
        "before calling list_library or get_library_entry; you may skip the library " +
        "entirely in that turn.",
    ),
  );
});

test("引用格式字面量与网页端 MARK 一致", () => {
  // apps/agent-web/src/thread/citations.ts 的 MARK 只认这两种形状。
  const paragraph = libraryParagraph();
  assert.ok(paragraph.includes("[[ref:<id>|<title>]]"));
  assert.ok(paragraph.includes("[[record:<id>|<title>]]"));
});

test("说明带 topic 返回整个主题、本周排前，目录同一主题翻一次即可", () => {
  const paragraph = libraryParagraph();
  assert.ok(paragraph.includes("with a topic it returns the whole topic, entries for this week first"));
  assert.ok(paragraph.includes("prefer passing a topic"));
  assert.ok(paragraph.includes("The catalogue for a topic only needs browsing once per conversation."));
});

test("记录引用的标题写日期加类型", () => {
  const paragraph = libraryParagraph();
  assert.ok(paragraph.includes("title made of its date and record type, such as 10月3日产检"));
});
