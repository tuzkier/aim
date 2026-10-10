import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const runtimeUrl = process.env.EVE_RUNTIME_URL ?? "";
const headers = {
  "x-aim-account-id": "acct_hz_001",
  "x-aim-family-id": "fam_001",
  "x-aim-pregnancy-id": "preg_001",
};

type EveEvent = {
  type: string;
  data?: Record<string, unknown>;
  meta?: { id?: string };
};

async function readSession(sessionId: string, startIndex = 0): Promise<EveEvent[]> {
  const response = await fetch(
    `${runtimeUrl}/eve/v1/session/${sessionId}/stream?startIndex=${startIndex}`,
    { headers, signal: AbortSignal.timeout(8_000) },
  );
  assert.equal(response.status, 200);
  assert.ok(response.body);

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  const events: EveEvent[] = [];
  let buffer = "";

  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";
      for (const line of lines) {
        if (!line.trim()) continue;
        const event = JSON.parse(line) as EveEvent;
        events.push(event);
        if (event.type === "session.waiting") {
          await reader.cancel();
          return events;
        }
      }
    }
  } finally {
    reader.releaseLock();
  }

  return events;
}

async function createSession(message: string): Promise<string> {
  const response = await fetch(`${runtimeUrl}/eve/v1/session`, {
    method: "POST",
    headers: { ...headers, "content-type": "application/json" },
    body: JSON.stringify({ message }),
  });
  assert.equal(response.status, 202);
  const body = (await response.json()) as { sessionId: string };
  assert.match(body.sessionId, /^wrun_/);
  return body.sessionId;
}

test("compiled runtime exposes only the intended root and specialist tools", async () => {
  const manifest = JSON.parse(
    await readFile(".eve/compile/compiled-agent-manifest.json", "utf8"),
  ) as {
    tools: Array<{ name: string }>;
    disabledFrameworkTools: string[];
    subagents: Array<{
      name: string;
      agent: { tools: Array<{ name: string }>; disabledFrameworkTools: string[] };
    }>;
  };

  const summary = JSON.parse(await readFile(".eve/agent-summary.json", "utf8")) as {
    tools: Array<{ name: string }>;
  };

  const BUSINESS_TOOLS = [
    "assign_task",
    "complete_task",
    "create_checkup_report",
    "create_knowledge",
    "create_record",
    "create_task",
    "delete_task",
    "echo_context",
    "forget_memory",
    "get_current_time",
    "get_guidance",
    "get_library_entry",
    "get_pregnancy_context",
    "list_library",
    "list_records",
    "list_tasks",
    "record_pregnancy_fact",
    "remember",
    "reschedule_task",
    "undo_operation",
  ];

  // 这几个要么是不经确认就能删的口子，要么是空壳。删除待办改由需确认的 delete_task 负责。
  const RETIRED_TOOLS = ["delete_record", "preview_task_change", "update_task"];

  // 能碰文件系统、shell 和外网的工具，一个都不该出现在孕期 App 的 agent 手上。
  const DANGEROUS_TOOLS = [
    "bash",
    "glob",
    "grep",
    "read_file",
    "write_file",
    "web_fetch",
    "web_search",
  ];

  const exposed = summary.tools.map((tool) => tool.name);
  for (const name of BUSINESS_TOOLS) {
    assert.ok(exposed.includes(name), `业务工具 ${name} 应当可用`);
  }
  for (const name of DANGEROUS_TOOLS) {
    assert.ok(!exposed.includes(name), `${name} 绝不该暴露给 agent`);
  }
  for (const name of RETIRED_TOOLS) {
    assert.ok(!exposed.includes(name), `${name} 已下线，不该再暴露`);
  }

  // 断言「有哪些不在」而不是「恰好是这些」：eve 升级会改摘要的 schema，
  // 逐字相等的清单每次都要跟着改，改多了就没人再认真看它了。
  // 真正要守住的是危险工具不出现，以及下面这份权威禁用清单不被悄悄改小。
  assert.deepEqual(
    manifest.disabledFrameworkTools.sort(),
    ["agent", "bash", "glob", "grep", "read_file", "web_fetch", "web_search", "write_file"],
  );

  const expert = manifest.subagents.find((subagent) => subagent.name === "pregnancy-expert");
  assert.ok(expert);
  assert.deepEqual(expert.agent.tools.map((tool) => tool.name), ["echo_context"]);
  assert.ok(expert.agent.disabledFrameworkTools.includes("write_file"));
});

test("route auth fails closed without the three Aim scope headers", { skip: !runtimeUrl }, async () => {
  const health = await fetch(`${runtimeUrl}/eve/v1/health`);
  assert.equal(health.status, 200);

  const unauthenticated = await fetch(`${runtimeUrl}/eve/v1/info`);
  assert.equal(unauthenticated.status, 401);
});

test("authenticated session preserves scope and supports cursor replay", { skip: !runtimeUrl }, async () => {
  const sessionId = await createSession("context");
  const events = await readSession(sessionId);
  const action = events.find((event) => event.type === "action.result");
  const result = action?.data?.result as
    | { toolName?: string; output?: Record<string, string> }
    | undefined;

  assert.equal(result?.toolName, "echo_context");
  assert.deepEqual(result?.output, {
    accountId: headers["x-aim-account-id"],
    familyId: headers["x-aim-family-id"],
    pregnancyId: headers["x-aim-pregnancy-id"],
    sessionId,
  });
  assert.equal(events.at(-1)?.type, "session.waiting");

  const ids = events.map((event) => event.meta?.id).filter(Boolean);
  assert.equal(new Set(ids).size, ids.length);

  const replay = await readSession(sessionId);
  assert.equal(replay[0]?.meta?.id, events[0]?.meta?.id);
});

test("root can delegate to the read-only pregnancy expert", { skip: !runtimeUrl }, async () => {
  const sessionId = await createSession("expert");
  const events = await readSession(sessionId);
  const called = events.find((event) => event.type === "subagent.called");
  const completed = events.find((event) => event.type === "subagent.completed");

  assert.equal(called?.data?.name, "pregnancy-expert");
  assert.equal(completed?.data?.subagentName, "pregnancy-expert");
  assert.equal(events.at(-1)?.type, "session.waiting");
  assert.equal(
    events.some((event) => String(event.data?.toolName).includes("preview_task_change")),
    false,
  );
});
