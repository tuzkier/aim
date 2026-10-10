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
    "severe belly pain",
    "a seizure",
    "confusion or fainting",
    "chest pain or shortness of breath",
    "waters breaking or fluid that keeps leaking",
    "the baby moving clearly less or not at all",
    "160/110",
    "severe headache or blurred vision",
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
