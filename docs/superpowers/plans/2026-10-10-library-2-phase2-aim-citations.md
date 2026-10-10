# 资料库 2.0 第 2 期：AIM 翻目录与引用 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AIM 回答孕期知识问题时先翻百科目录、读相关条目、在回答里引用；引用在对话里显示为可点的来源胶囊，点开跳到原生的百科条目或记录详情；资料库各页「问 AIM」带上可引用的编号。

**Architecture:** API 新增两个只读内部接口 `list-library`、`get-library-entry`（复用第 1 期的 `get_encyclopedia()`），Agent 新增同名工具；指令规定引用标记 `[[ref:<id>|<标题>]]` / `[[record:<uuid>|<标题>]]`。agent-web 的 `MarkdownText.renderInline` 解析标记渲染胶囊，经 `openNative` 新增 `kind: "encyclopedia"`；iOS 的 `AgentWebRoute` / `AgentDestination` 加百科分支。

**Tech Stack:** FastAPI；Eve agent（TypeScript + zod）；React（assistant-ui）+ vitest；SwiftUI + XCTest。

规格：`docs/superpowers/specs/2026-10-09-library-2-design.md` §6.5、§7.1、§7.2。

## Global Constraints

- 所有面向用户的文字、注释、提交信息用简体中文。
- 引用标记格式严格为 `[[ref:<百科 id>|<标题>]]` 与 `[[record:<记录 uuid>|<标题>]]`；百科 id 形如 `<主题>.<短名>`（`[a-z]+\.[a-z0-9-]+`）。只能引用本轮工具返回过的编号；百科没覆盖的问题照常回答但不得编造引用。
- 格式不合法的标记：去掉方括号与前缀，只显示标题（无标题则显示原文去括号）；不得渲染成可点胶囊。
- `list_library` 返回目录（不含正文）；`get_library_entry` 返回全文；两者为只读工具（不进「最近处理」台账）。
- 生产不加载草稿：接口与工具只暴露 `get_encyclopedia()` 已加载的条目（与第 1 期一致）。
- iOS 对不存在的百科编号显示「这条资料已下线」，不报错、不崩。
- 测试：API 在 `services/api` 下 `PYTHONPATH=src python3 -m pytest`；Agent `make -C services/agent test`；web `npm test --prefix apps/agent-web`（vitest）与 `npm run build --prefix apps/agent-web`；iOS 用 iPhone 18 Pro。只可重建 api 容器。

---

### Task 1: 内部接口、Agent 工具与指令

**Files:**
- Modify: `services/api/src/aim_api/contexts/agent_access/adapters/inbound/http/router.py`（请求模型、`_list_library`、`_get_library_entry`、两个路由；如有工具白名单 `authorize_tool` / 工具名集合，一并登记）
- Create: `services/agent/agent/tools/list_library.ts`、`services/agent/agent/tools/get_library_entry.ts`
- Modify: `services/agent/agent/tools/list_records.ts`（type 枚举加 `question`、`knowledge`）
- Modify: `services/agent/agent/instructions.md`
- Modify: `services/agent/tests/runtime-gate.test.ts`（`BUSINESS_TOOLS`）
- Modify: `apps/agent-web/src/tools/labels.ts`（`READ_ONLY_TOOLS`、`TOOL_TITLES`）
- Test: `services/api/tests/integration/agent_access/test_library_tools.py`
- 重新生成：`contracts/agent-tools/openapi.json`

**Interfaces:**
- Produces：
  - `POST /internal/agent-tools/list-library`，body `{topic?: str, week?: int(0–45)}` → `data = {"topics": [...], "entries": [{id, topic, title, aliases, weeks, summary}]}`（即 `get_encyclopedia().catalog(topic=, week=)`）；`week` 缺省时用当前孕期孕周（`pregnancy.gestational_age().weeks`，夹到 4–42），传 `null` 以外的值则用传入值。
  - `POST /internal/agent-tools/get-library-entry`，body `{id: str}` → `data = get_encyclopedia().detail(id)`；不存在返回 `ok: true, data: {"found": false, "id": id}`（不抛错，让模型能如实说「没有这条」）。
  - Agent 工具 `list_library({topic?, week?})`、`get_library_entry({id})`。

- [ ] **Step 1: API 测试（先失败）**

`test_library_tools.py`（照 `tests/integration/agent_access/` 里已有用例的写法构造服务头与孕期）：

```python
def test_list_library_defaults_to_the_current_week(...):
    # 孕 25 周的孕期调用 list-library（不传 week）→ entries 非空、不含 sections、
    # 每条的 weeks 为 None 或覆盖 25 周；按 week_rank 排序（第一条 weeks 起点最接近 25）
    ...

def test_list_library_filters_by_topic(...):
    # topic="diet" → 全部 entries 的 topic == "diet"

def test_get_library_entry_returns_the_full_text_or_not_found(...):
    # id="body.fetal-movement" → data["sections"] 非空、data["title"] == "胎动与数胎动"
    # id="body.nope" → data == {"found": False, "id": "body.nope"}
```

**写出完整代码**：断言用上面注释里的具体条件；服务头、孕期构造照现有 `test_pregnancy_context_tool.py`。

- [ ] **Step 2: API 实现**

```python
class ListLibraryRequest(BaseModel):
    topic: str | None = None
    week: int | None = Field(default=None, ge=0, le=45)


class GetLibraryEntryRequest(BaseModel):
    id: str = Field(min_length=1, max_length=100)


async def _list_library(session, context: AgentToolContext, body: dict[str, Any]):
    week = body.get("week")
    if week is None:
        pregnancy = await SqlAlchemyPregnancyRepository(session).get(context.pregnancy_id)  # 以 _get_context 的取法为准
        week = pregnancy.gestational_age().weeks if pregnancy else None
    if week is not None:
        week = min(max(week, 4), 42)
    catalog = get_encyclopedia().catalog(topic=body.get("topic"), week=week)
    return (catalog, f"翻了 {len(catalog['entries'])} 条资料目录")


async def _get_library_entry(session, context: AgentToolContext, body: dict[str, Any]):
    detail = get_encyclopedia().detail(body["id"])
    if detail is None:
        return ({"found": False, "id": body["id"]}, "没有这条资料")
    return (detail, f"读了「{detail['title']}」")
```

路由（只读，不传 `write=True`）：

```python
@router.post("/list-library", response_model=ToolResult, include_in_schema=False)
async def list_library_endpoint(request: Request, payload: ListLibraryRequest):
    return await _run(request, "list_library", payload, _list_library)


@router.post("/get-library-entry", response_model=ToolResult, include_in_schema=False)
async def get_library_entry_endpoint(request: Request, payload: GetLibraryEntryRequest):
    return await _run(request, "get_library_entry", payload, _get_library_entry)
```

（孕期读取方式照 `_get_context`；`get_encyclopedia` 从 `aim_api.contexts.guidance.application.queries.get_encyclopedia` 导入；若架构测试限制 agent_access 导入 guidance，照 `_red_flags` 导入 `get_safety_rules` 的方式。）

- [ ] **Step 3: Agent 工具**

`services/agent/agent/tools/list_library.ts`：

```ts
import { defineTool } from "eve/tools";
import { z } from "zod";
import { callBusinessApi } from "../lib/business-api/client.ts";
import { toolResultSchema } from "../lib/business-api/tool-result-schema.ts";

export default defineTool({
  description:
    "List the pregnancy encyclopedia catalog (titles, aliases, weeks, one-line summaries; no full text). " +
    "Defaults to entries relevant to the user's current week; pass topic to browse one topic " +
    "(checkup, body, diet, life, birth, paperwork).",
  inputSchema: z.object({
    topic: z.enum(["checkup", "body", "diet", "life", "birth", "paperwork"]).optional(),
    week: z.number().int().min(0).max(45).optional(),
  }),
  outputSchema: toolResultSchema,
  async execute(input, ctx) {
    return callBusinessApi(ctx, "/internal/agent-tools/list-library", input);
  },
});
```

`get_library_entry.ts`：同样结构，`inputSchema: z.object({ id: z.string().regex(/^[a-z]+\.[a-z0-9-]+$/) })`，description「Read one encyclopedia entry in full by its id (from list_library).」，调用 `/internal/agent-tools/get-library-entry`。

`list_records.ts` 的 type 枚举加 `"question"`、`"knowledge"`。`runtime-gate.test.ts` 的 `BUSINESS_TOOLS` 加两个新工具名。`labels.ts`：`READ_ONLY_TOOLS` 加 `"list_library"`、`"get_library_entry"`；`TOOL_TITLES` 加 `list_library: "翻资料目录"`、`get_library_entry: "读资料"`。

- [ ] **Step 4: 指令**

在 instructions.md 读工具列表处补上 `list_library`、`get_library_entry`，并加一段（英文、80 列）：

```
For pregnancy knowledge questions (checkups, symptoms, food, daily life, birth,
paperwork), first call list_library (it defaults to the user's current week;
pass a topic when the question is clearly about one) and read the one or two
most relevant entries with get_library_entry. Base your answer on what those
entries say. When you use an entry, cite it at the end of the sentence as
[[ref:<id>|<title>]] using the exact id and title the tool returned. When you
use one of the family's own records, cite it as [[record:<id>|<title>]].
Only cite ids that a tool returned in this conversation; never invent one.
If the encyclopedia has nothing relevant, answer normally without a citation.
Paperwork entries only point to official channels: never state amounts,
eligibility or numbers of days as facts.
Urgent symptoms still come first: the emergency rules above apply before any
library lookup.
```

- [ ] **Step 5: 测试并提交**

Run: `cd services/api && PYTHONPATH=src python3 -m pytest -q && cd ../.. && make contracts && git diff --stat contracts && make -C services/agent test && npm test --prefix apps/agent-web`
```bash
git add services/api services/agent apps/agent-web/src/tools/labels.ts contracts
git commit -m "feat(agent): AIM 翻资料目录与读条目的工具，回答引用资料"
```

---

### Task 2: 对话里的引用胶囊（agent-web）

**Files:**
- Create: `apps/agent-web/src/thread/citations.ts`（纯函数解析）
- Modify: `apps/agent-web/src/thread/MarkdownText.tsx`（`renderInline` 接入）
- Modify: `apps/agent-web/src/bridge.ts`（`openNative` 的 kind 加 `"encyclopedia"`）
- Modify: 样式文件（胶囊样式，放在现有 CSS 中与 `.aim-*` 类同处，以仓库实际样式文件为准）
- Test: `apps/agent-web/src/thread/citations.test.ts`

**Interfaces:**
- Produces：`parseCitations(text: string): Array<{kind: "text", text: string} | {kind: "ref", id: string, title: string} | {kind: "record", id: string, title: string}>`

- [ ] **Step 1: 测试（先失败）**

```ts
import { describe, expect, it } from "vitest";
import { parseCitations } from "./citations";

describe("parseCitations", () => {
  it("切出百科与记录引用", () => {
    expect(parseCitations("糖耐量前要空腹[[ref:checkup.ogtt|糖耐量]]。上次结果[[record:0b6c1a2e-1111-4a2b-9c3d-123456789abc|10月3日产检]]")).toEqual([
      { kind: "text", text: "糖耐量前要空腹" },
      { kind: "ref", id: "checkup.ogtt", title: "糖耐量" },
      { kind: "text", text: "。上次结果" },
      { kind: "record", id: "0b6c1a2e-1111-4a2b-9c3d-123456789abc", title: "10月3日产检" },
    ]);
  });

  it("格式不合法时只留标题，不成为可点引用", () => {
    expect(parseCitations("见[[ref:不合法|某条]]")).toEqual([
      { kind: "text", text: "见" },
      { kind: "text", text: "某条" },
    ]);
    expect(parseCitations("见[[record:not-a-uuid|某次]]")).toEqual([
      { kind: "text", text: "见" },
      { kind: "text", text: "某次" },
    ]);
  });

  it("缺标题时用编号兜底的文字，不渲染胶囊", () => {
    expect(parseCitations("[[ref:checkup.ogtt]]")).toEqual([{ kind: "text", text: "checkup.ogtt" }]);
  });

  it("没有标记时原样返回", () => {
    expect(parseCitations("普通的一句话")).toEqual([{ kind: "text", text: "普通的一句话" }]);
  });
});
```

Run: `npm test --prefix apps/agent-web -- citations` → FAIL（模块不存在）。

- [ ] **Step 2: 实现**

`citations.ts`：

```ts
/**
 * AIM 回答里的引用标记：[[ref:<百科编号>|<标题>]]、[[record:<记录编号>|<标题>]]。
 *
 * 只有格式完全合法的才变成可点的来源胶囊；其余去掉方括号只留文字——
 * 模型偶尔会写坏标记，宁可少一个可点入口，也不能把一个跳不过去的编号做成按钮。
 */
export type CitationPiece =
  | { kind: "text"; text: string }
  | { kind: "ref"; id: string; title: string }
  | { kind: "record"; id: string; title: string };

const MARK = /\[\[(ref|record):([^\]|]+)(?:\|([^\]]+))?\]\]/g;
const REF_ID = /^[a-z]+\.[a-z0-9-]+$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const parseCitations = (text: string): CitationPiece[] => {
  const pieces: CitationPiece[] = [];
  let last = 0;
  for (const match of text.matchAll(MARK)) {
    const [whole, kind, rawId, rawTitle] = match;
    const index = match.index ?? 0;
    if (index > last) pieces.push({ kind: "text", text: text.slice(last, index) });
    const id = rawId!.trim();
    const title = rawTitle?.trim();
    const valid = kind === "ref" ? REF_ID.test(id) : UUID.test(id);
    if (valid && title) {
      pieces.push({ kind: kind as "ref" | "record", id, title });
    } else {
      pieces.push({ kind: "text", text: title || id });
    }
    last = index + whole.length;
  }
  if (last < text.length) pieces.push({ kind: "text", text: text.slice(last) });
  return pieces.length > 0 ? pieces : [{ kind: "text", text }];
};
```

`MarkdownText.tsx` 的 `renderInline`：先 `parseCitations(text)`，对 `text` 片段沿用原来的加粗切分，对引用片段渲染：

```tsx
<button
  key={key}
  type="button"
  className="aim-citation"
  onClick={() => openNative({ kind: piece.kind === "ref" ? "encyclopedia" : "record", id: piece.id })}
>
  {piece.kind === "ref" ? "📖" : "🗂"} {piece.title}
</button>
```

（用文字图标而不是 SVG，保持与现有样式一致；若仓库已有图标组件按惯例用。）`bridge.ts` 的 `openNative` 参数类型改为 `{ kind: "record" | "task" | "knowledge" | "encyclopedia"; id: string }`。胶囊样式：小号圆角背景、与正文同行内联、可点高亮，颜色取现有 accent 变量。

再加一条 `MarkdownText` 层面的测试（若已有 MarkdownText 测试文件则追加；否则在 `citations.test.ts` 里用 `@testing-library/react` 渲染——仅当项目已依赖它；未依赖就只测纯函数）。

- [ ] **Step 3: 测试、构建并提交**

Run: `npm test --prefix apps/agent-web && npm run build --prefix apps/agent-web`
```bash
git add apps/agent-web
git commit -m "feat(web): AIM 回答里的资料引用显示为可点的来源胶囊"
```

（构建产物 `dist` 不进版本库；本地网关挂载 dist，构建后模拟器即生效。）

---

### Task 3: iOS 跳转与「问 AIM」上下文

**Files:**
- Modify: `apps/ios/AimApp/Features/Agent/AgentWebView.swift`（`AgentWebRoute` 加 `.encyclopedia(String)`）
- Modify: `apps/ios/AimApp/Features/Agent/AgentView.swift`（`AgentDestination` 加 `.encyclopedia(String)`；`resolve`；`destinationView` 渲染 `EncyclopediaEntryView`）
- Modify: `apps/ios/AimApp/Features/Library/EncyclopediaEntryView.swift`（404 时显示「这条资料已下线」）
- Modify: `apps/ios/AimApp/Features/Library/LibraryCatalog.swift`（`agentContext` / `askContext` 对 checkups、symptoms 带最近 5 条记录的编号）
- Test: `apps/ios/AimApp/Tests/AgentWebRouteTests.swift`（若已有路由测试文件则追加，否则新建并登记 pbxproj，编号以现有最大编号 +1，照 `Tests/EncyclopediaCatalogTests.swift` 的四处登记）、`apps/ios/AimApp/Tests/LibraryCatalogTests.swift`

**Interfaces:**
- Consumes：Task 2 的 `openNative({kind: "encyclopedia", id})`（消息体 `{"kind": "encyclopedia", "id": "<百科编号>"}`）。
- Produces：`AgentWebRoute.encyclopedia(String)`、`AgentDestination.encyclopedia(String)`。

- [ ] **Step 1: 测试（先失败）**

```swift
func testEncyclopediaRouteKeepsTheEntryID() {
    XCTAssertEqual(AgentWebRoute(body: ["kind": "encyclopedia", "id": "checkup.ogtt"]), .encyclopedia("checkup.ogtt"))
    XCTAssertNil(AgentWebRoute(body: ["kind": "encyclopedia", "id": "不合法"]))
    XCTAssertEqual(AgentWebRoute(body: ["kind": "record", "id": UUID().uuidString]).map { if case .record = $0 { return true } else { return false } }, true)
}
```

`LibraryCatalogTests` 加：checkups 的 `agentContext` 摘要包含最近一条产检记录的 `uuidString`；symptoms 同理；记录超过 5 条时只带最近 5 条。

- [ ] **Step 2: 实现**

`AgentWebRoute.init?(body:)`：`kind == "encyclopedia"` 时不走 UUID 解析，要求 `id` 匹配 `^[a-z]+\.[a-z0-9-]+$`，`self = .encyclopedia(id)`。

`AgentDestination` 加 `case encyclopedia(String)`，`id` 为 `"encyclopedia-\(id)"`；`resolve` 对 `.encyclopedia` 直接返回 `.encyclopedia(id)`（不预取：详情页自己加载并处理 404）；`destinationView` 渲染 `EncyclopediaEntryView(entryID: id, store: destinations.libraryStore, agentStore: destinations.agentStore)`（属性名以现有 `AgentDestinations` 为准）。

`EncyclopediaEntryView` 加载失败时：若错误是 404（以 `APIError` 实际的状态码表达为准），显示「这条资料已下线」且不提供重试；其他错误维持原有可重试提示。

`LibraryCatalog`：checkups 与 symptoms 的 `agentContext(from:)` 摘要末尾加一行：

```
记录编号：<uuid>（<M月d日> <displayTitle>）；…   // 最近 5 条，按时间倒序
```

让 AIM 可以 `[[record:<uuid>|…]]` 引用。

- [ ] **Step 3: 测试并提交**

Run: 单元测试 `-only-testing:AimAppTests`；UI 回归 `testEncyclopediaTopicEntryAndAskAIM`。
```bash
git add apps/ios
git commit -m "feat(ios): 点 AIM 回答里的资料引用跳到原生百科条目；资料页问 AIM 带记录编号"
```

---

### Task 4: 端到端核对

- [ ] 重建 api（`docker compose --env-file .env --profile local -f infrastructure/compose/compose.yaml up -d --build api eve`——**本任务需同时重建 eve**，因为 Agent 工具与指令改了；不得停止其他容器）。
- [ ] `npm run build --prefix apps/agent-web`。
- [ ] 写临时 XCUITest：注册、填预产期、切到 AIM、输入「糖耐量要空腹吗」并发送，等待回答出现，断言 webView 中存在含「糖耐量」的按钮（引用胶囊），点击后出现 `navigationBars["糖耐量"]`（或条目标题）。跑完删除该临时用例，不提交。
- [ ] 若本地 `.env` 中 `EVE_USE_MOCK_MODEL=1` 或无模型密钥，跳过模型相关断言，在报告中说明。
- [ ] 结果写入报告；无代码提交。
