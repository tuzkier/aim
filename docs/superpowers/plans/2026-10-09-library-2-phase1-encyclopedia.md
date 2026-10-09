# 资料库 2.0 第 1 期：百科底座 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 资料库有一套预置的、可按主题和孕周浏览的孕期百科：API 提供目录与单条接口，iOS 资料库新增「这周读什么」与「孕期百科」两个区、主题页和条目详情（可顺着条目问 AIM）。

**Architecture:** 百科内容是 `content/encyclopedia/<主题>.yaml`，API 进程启动时加载并校验一次、缓存在内存；草稿文件只有 `AIM_CONTENT_INCLUDE_DRAFTS=1` 时加载（本地开、生产关）。iOS 一次拉取完整目录（约 60 条摘要），本地按孕周挑选与排序；条目全文按需拉取。现有六张分类卡与详情页不动，只挪到「我的档案」小标题下。

**Tech Stack:** FastAPI + PyYAML + jsonschema（测试）、SwiftUI（iOS 17+，`@Observable`）、XCTest / XCUITest。

规格：`docs/superpowers/specs/2026-10-09-library-2-design.md`（第 4、6 节与第 8 节第 1 期）。

## Global Constraints

- 所有面向用户的文字、注释、提交信息用简体中文。
- 百科主题固定六个，顺序即展示顺序：`checkup` 产检项目、`body` 身体变化与不适、`diet` 饮食营养、`life` 生活与运动、`birth` 待产与分娩、`paperwork` 办事与政策。
- 条目编号 `<主题>.<短名>`（短名只含小写字母、数字、连字符），发布后不改名。
- 条目字段限制：`title` ≤16 字；`aliases` ≤6 个；`weeks` 为 `[起, 止]`，4–42；`summary` ≤60 字；`sections` 1–4 段，`heading` ≤12 字、`text` ≤300 字；`ask` 2–3 个，每个 ≤24 字；`kind: policy` 必须有 `link`。
- 草稿不上线：生产编排必须显式设置 `AIM_CONTENT_INCLUDE_DRAFTS: "0"`。
- `content/nutrition` 集合与 `/api/v1/content/nutrition` 接口**保留**（旧版 App 仍在读），新版 iOS 不再读取它。
- iOS 新文件要在 `apps/ios/AimApp.xcodeproj/project.pbxproj` 手工登记四处（PBXBuildFile、PBXFileReference、所在 group 的 children、对应 target 的 Sources 构建阶段），编号从 `…155` 起，格式照抄 `Features/Home/WeeklyContent.swift`（App）与 `Tests/HomeDashboardTests.swift`（测试）现有的四处登记。
- 模拟器用 iPhone 18 Pro；UI 用例连本地 `make dev` 栈。已知有两条既有 UI 用例失败，与本期无关。

## 文件结构

API（`services/api/`）：
- Create `src/aim_api/contexts/guidance/domain/encyclopedia.py` —— 百科领域对象：主题表、条目、目录与详情视图。不碰文件系统。
- Create `src/aim_api/contexts/guidance/application/queries/get_encyclopedia.py` —— 从目录加载与校验 YAML、草稿开关、进程内缓存。
- Modify `src/aim_api/contexts/guidance/adapters/inbound/http/router.py` —— 两个接口。
- Modify `src/aim_api/bootstrap.py` —— 启动时加载一次，坏内容让启动失败。
- Modify `tests/conftest.py` —— 测试进程打开草稿开关。
- Create `tests/application/guidance/test_encyclopedia.py`、`tests/integration/test_encyclopedia_api.py`、`tests/contract/content/test_encyclopedia_content.py`、`tests/contract/test_deploy_config.py`。

内容：
- Create `content/encyclopedia/schema.json` 与 `checkup.yaml`、`body.yaml`、`diet.yaml`、`life.yaml`、`birth.yaml`、`paperwork.yaml`。

编排：
- Modify `infrastructure/compose/compose.yaml`（本地开草稿）、`infrastructure/compose/compose.prod.yaml`（生产关草稿）。

iOS（`apps/ios/AimApp/`）：
- Create `Features/Library/EncyclopediaModels.swift` —— 目录、主题、条目模型与本地挑选逻辑。
- Create `Features/Library/EncyclopediaSections.swift` —— 资料库首页的「这周读什么」横滑卡与「孕期百科」主题网格。
- Create `Features/Library/EncyclopediaTopicView.swift` —— 主题页与通用条目行。
- Create `Features/Library/EncyclopediaEntryView.swift` —— 条目详情（问问 AIM、相关条目、来源）。
- Create `Tests/EncyclopediaCatalogTests.swift`。
- Modify `Clients/BusinessAPIClient/BusinessRepository.swift`、`Features/Library/LibraryStore.swift`、`Features/Library/LibraryCatalog.swift`、`Features/Library/LibraryView.swift`、`Features/Library/LibraryCategoryDetail.swift`、`UITests/CoreJourneyUITests.swift`、`Tests/LibraryCatalogTests.swift`（如有对 `collectionSizes["nutrition"]` 的断言）。

---

### Task 1: 百科领域对象与加载器

**Files:**
- Create: `content/encyclopedia/schema.json`
- Create: `services/api/src/aim_api/contexts/guidance/domain/encyclopedia.py`
- Create: `services/api/src/aim_api/contexts/guidance/application/queries/get_encyclopedia.py`
- Test: `services/api/tests/application/guidance/test_encyclopedia.py`

**Interfaces:**
- Produces（后续任务依赖）：
  - `aim_api.contexts.guidance.domain.encyclopedia`：`TOPICS: tuple[tuple[str, str], ...]`、`EntrySection(heading, text)`、`EncyclopediaEntry`（字段见下）、`Encyclopedia(entries)`，方法 `get(entry_id) -> EncyclopediaEntry | None`、`catalog(*, topic=None, week=None) -> dict`、`detail(entry_id) -> dict | None`。
  - `aim_api.contexts.guidance.application.queries.get_encyclopedia`：`EncyclopediaError`、`load_encyclopedia(directory: Path, *, include_drafts: bool) -> Encyclopedia`、`get_encyclopedia() -> Encyclopedia`（`lru_cache`）、常量 `INCLUDE_DRAFTS_ENV = "AIM_CONTENT_INCLUDE_DRAFTS"`。
  - 目录 JSON：`{"topics": [{"id","name","count"}], "entries": [{"id","topic","title","aliases","weeks","summary"}]}`；`weeks` 为 `[起, 止]` 或 `null`。
  - 详情 JSON：目录条目字段 + `sections: [{heading,text}]`、`ask: [str]`、`related: [{id,title}]`、`kind`、`link`、`source`、`source_url`、`reviewed_at`、`review_status`。

- [ ] **Step 1: 写 schema**

`content/encyclopedia/schema.json`：

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "required": ["id", "version", "source", "source_url", "review_status", "entries"],
  "properties": {
    "id": {"type": "string", "pattern": "^encyclopedia-[a-z]+$"},
    "version": {"type": "string"},
    "source": {"type": "string", "minLength": 2},
    "source_url": {"type": "string", "format": "uri"},
    "reviewed_at": {"type": ["string", "null"], "format": "date"},
    "review_status": {"enum": ["draft", "reviewed"]},
    "entries": {"type": "array", "minItems": 1, "items": {"$ref": "#/$defs/entry"}}
  },
  "if": {"properties": {"review_status": {"const": "reviewed"}}},
  "then": {"required": ["reviewed_at"], "properties": {"reviewed_at": {"type": "string"}}},
  "$defs": {
    "entry": {
      "type": "object",
      "additionalProperties": false,
      "required": ["id", "title", "summary", "sections", "ask"],
      "properties": {
        "id": {"type": "string", "pattern": "^[a-z]+\\.[a-z0-9-]+$"},
        "title": {"type": "string", "minLength": 2, "maxLength": 16},
        "aliases": {"type": "array", "maxItems": 6, "items": {"type": "string", "minLength": 1, "maxLength": 12}},
        "weeks": {"type": "array", "minItems": 2, "maxItems": 2, "items": {"type": "integer", "minimum": 4, "maximum": 42}},
        "summary": {"type": "string", "minLength": 8, "maxLength": 60},
        "sections": {
          "type": "array", "minItems": 1, "maxItems": 4,
          "items": {
            "type": "object", "additionalProperties": false, "required": ["heading", "text"],
            "properties": {
              "heading": {"type": "string", "minLength": 2, "maxLength": 12},
              "text": {"type": "string", "minLength": 10, "maxLength": 300}
            }
          }
        },
        "ask": {"type": "array", "minItems": 2, "maxItems": 3, "items": {"type": "string", "minLength": 4, "maxLength": 24}},
        "related": {"type": "array", "maxItems": 5, "items": {"type": "string"}},
        "kind": {"enum": ["policy"]},
        "link": {"type": "string", "format": "uri"}
      },
      "if": {"required": ["kind"]},
      "then": {"required": ["link"]}
    }
  }
}
```

- [ ] **Step 2: 写失败的测试**

`services/api/tests/application/guidance/test_encyclopedia.py`：

```python
from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from aim_api.contexts.guidance.application.queries.get_encyclopedia import (
    EncyclopediaError,
    load_encyclopedia,
)


def _write(directory: Path, topic: str, entries: list[dict], *, status: str = "reviewed") -> None:
    document = {
        "id": f"encyclopedia-{topic}",
        "version": "1.0.0",
        "source": "测试来源",
        "source_url": "https://example.com",
        "reviewed_at": "2026-10-09" if status == "reviewed" else None,
        "review_status": status,
        "entries": entries,
    }
    (directory / f"{topic}.yaml").write_text(
        yaml.safe_dump(document, allow_unicode=True), encoding="utf-8"
    )


def _entry(entry_id: str, *, weeks: tuple[int, int] | None = None, **extra) -> dict:
    entry = {
        "id": entry_id,
        "title": f"标题{entry_id.split('.')[-1]}",
        "summary": "一句话摘要，说清楚这条讲什么",
        "sections": [{"heading": "是什么", "text": "这是一段足够长的正文内容。"}],
        "ask": ["这个要注意什么", "什么时候找医生"],
    }
    if weeks is not None:
        entry["weeks"] = list(weeks)
    entry.update(extra)
    return entry


def test_drafts_are_skipped_unless_included(tmp_path: Path) -> None:
    _write(tmp_path, "body", [_entry("body.nausea")], status="draft")
    _write(tmp_path, "diet", [_entry("diet.iron")])

    published = load_encyclopedia(tmp_path, include_drafts=False)
    everything = load_encyclopedia(tmp_path, include_drafts=True)

    assert [e.id for e in published.entries] == ["diet.iron"]
    assert [e.id for e in everything.entries] == ["body.nausea", "diet.iron"]


def test_entries_follow_topic_order_not_file_name_order(tmp_path: Path) -> None:
    _write(tmp_path, "paperwork", [_entry("paperwork.leave", kind="policy", link="https://example.com/a")])
    _write(tmp_path, "checkup", [_entry("checkup.nt")])

    encyclopedia = load_encyclopedia(tmp_path, include_drafts=True)

    assert [e.id for e in encyclopedia.entries] == ["checkup.nt", "paperwork.leave"]


def test_entry_id_must_carry_its_topic_prefix(tmp_path: Path) -> None:
    _write(tmp_path, "body", [_entry("diet.iron")])
    with pytest.raises(EncyclopediaError, match="body"):
        load_encyclopedia(tmp_path, include_drafts=True)


def test_duplicate_ids_are_rejected(tmp_path: Path) -> None:
    _write(tmp_path, "body", [_entry("body.cramp"), _entry("body.cramp")])
    with pytest.raises(EncyclopediaError, match="body.cramp"):
        load_encyclopedia(tmp_path, include_drafts=True)


def test_policy_entries_need_an_official_link(tmp_path: Path) -> None:
    _write(tmp_path, "paperwork", [_entry("paperwork.allowance", kind="policy")])
    with pytest.raises(EncyclopediaError, match="link"):
        load_encyclopedia(tmp_path, include_drafts=True)


def test_invalid_week_range_is_rejected(tmp_path: Path) -> None:
    _write(tmp_path, "body", [_entry("body.edema", weeks=(30, 20))])
    with pytest.raises(EncyclopediaError, match="weeks"):
        load_encyclopedia(tmp_path, include_drafts=True)


def test_unknown_topic_files_are_rejected(tmp_path: Path) -> None:
    _write(tmp_path, "gossip", [_entry("gossip.x")])
    with pytest.raises(EncyclopediaError, match="gossip"):
        load_encyclopedia(tmp_path, include_drafts=True)


def test_missing_directory_is_an_empty_encyclopedia(tmp_path: Path) -> None:
    assert load_encyclopedia(tmp_path / "nope", include_drafts=True).entries == ()


def test_catalog_for_a_week_ranks_the_closest_start_first(tmp_path: Path) -> None:
    _write(tmp_path, "body", [
        _entry("body.early", weeks=(4, 12)),
        _entry("body.mid", weeks=(20, 30)),
        _entry("body.always"),
        _entry("body.now", weeks=(24, 28)),
    ])
    encyclopedia = load_encyclopedia(tmp_path, include_drafts=True)

    entries = encyclopedia.catalog(week=25)["entries"]

    # 全程适用的条目也算覆盖本周，但排在有明确孕周的条目之后。
    assert [e["id"] for e in entries] == ["body.now", "body.mid", "body.always"]


def test_catalog_lists_topics_with_counts_and_filters_by_topic(tmp_path: Path) -> None:
    _write(tmp_path, "diet", [_entry("diet.iron"), _entry("diet.fish")])
    _write(tmp_path, "body", [_entry("body.cramp", weeks=(20, 36))])
    encyclopedia = load_encyclopedia(tmp_path, include_drafts=True)

    catalog = encyclopedia.catalog()
    by_topic = encyclopedia.catalog(topic="diet")

    assert catalog["topics"] == [
        {"id": "body", "name": "身体变化与不适", "count": 1},
        {"id": "diet", "name": "饮食营养", "count": 2},
    ]
    assert catalog["entries"][0] == {
        "id": "body.cramp", "topic": "body", "title": "标题cramp",
        "aliases": [], "weeks": [20, 36], "summary": "一句话摘要，说清楚这条讲什么",
    }
    assert [e["id"] for e in by_topic["entries"]] == ["diet.iron", "diet.fish"]


def test_detail_resolves_related_titles_and_drops_unpublished_links(tmp_path: Path) -> None:
    _write(tmp_path, "diet", [_entry("diet.iron", related=["diet.fish", "body.secret"]), _entry("diet.fish")])
    _write(tmp_path, "body", [_entry("body.secret")], status="draft")
    encyclopedia = load_encyclopedia(tmp_path, include_drafts=False)

    detail = encyclopedia.detail("diet.iron")

    assert detail is not None
    assert detail["related"] == [{"id": "diet.fish", "title": "标题fish"}]
    assert detail["sections"] == [{"heading": "是什么", "text": "这是一段足够长的正文内容。"}]
    assert detail["ask"] == ["这个要注意什么", "什么时候找医生"]
    assert detail["review_status"] == "reviewed"
    assert detail["reviewed_at"] == "2026-10-09"
    assert encyclopedia.detail("diet.nope") is None
```

- [ ] **Step 3: 跑测试确认失败**

Run: `cd services/api && python3 -m pytest tests/application/guidance/test_encyclopedia.py -q`
Expected: FAIL，`ModuleNotFoundError: ... get_encyclopedia`

- [ ] **Step 4: 写领域对象**

`services/api/src/aim_api/contexts/guidance/domain/encyclopedia.py`：

```python
"""孕期百科的领域对象。

百科是经人工审核、随版本发布的只读知识，按主题与孕周组织。
这里只描述条目长什么样、怎么按孕周挑选；文件读取在应用层。
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

#: 主题顺序就是 App 里的展示顺序。
TOPICS: tuple[tuple[str, str], ...] = (
    ("checkup", "产检项目"),
    ("body", "身体变化与不适"),
    ("diet", "饮食营养"),
    ("life", "生活与运动"),
    ("birth", "待产与分娩"),
    ("paperwork", "办事与政策"),
)


@dataclass(frozen=True, slots=True)
class EntrySection:
    heading: str
    text: str


@dataclass(frozen=True, slots=True)
class EncyclopediaEntry:
    id: str
    topic: str
    title: str
    aliases: tuple[str, ...]
    #: `(起, 止)`；`None` 表示全程适用。
    weeks: tuple[int, int] | None
    summary: str
    sections: tuple[EntrySection, ...]
    ask: tuple[str, ...]
    related: tuple[str, ...]
    kind: str | None
    link: str | None
    source: str
    source_url: str
    reviewed_at: str | None
    review_status: str

    def covers(self, week: int) -> bool:
        if self.weeks is None:
            return True
        return self.weeks[0] <= week <= self.weeks[1]

    def week_rank(self, week: int) -> tuple[int, int]:
        """越小越该现在读：适用期起点离本周越近越靠前，全程适用的排最后。"""
        if self.weeks is None:
            return (1, 0)
        return (0, abs(week - self.weeks[0]))

    def summary_view(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "topic": self.topic,
            "title": self.title,
            "aliases": list(self.aliases),
            "weeks": list(self.weeks) if self.weeks else None,
            "summary": self.summary,
        }


@dataclass(frozen=True, slots=True)
class Encyclopedia:
    entries: tuple[EncyclopediaEntry, ...]

    def get(self, entry_id: str) -> EncyclopediaEntry | None:
        return next((entry for entry in self.entries if entry.id == entry_id), None)

    def catalog(self, *, topic: str | None = None, week: int | None = None) -> dict[str, Any]:
        selected = [
            entry
            for entry in self.entries
            if (topic is None or entry.topic == topic) and (week is None or entry.covers(week))
        ]
        if week is not None:
            # sort 是稳定的：同一档内保持内容文件里的顺序。
            selected.sort(key=lambda entry: entry.week_rank(week))
        counts = {name: 0 for name, _ in TOPICS}
        for entry in self.entries:
            counts[entry.topic] += 1
        return {
            "topics": [
                {"id": topic_id, "name": name, "count": counts[topic_id]}
                for topic_id, name in TOPICS
                if counts[topic_id]
            ],
            "entries": [entry.summary_view() for entry in selected],
        }

    def detail(self, entry_id: str) -> dict[str, Any] | None:
        entry = self.get(entry_id)
        if entry is None:
            return None
        titles = {item.id: item.title for item in self.entries}
        return {
            **entry.summary_view(),
            "sections": [{"heading": s.heading, "text": s.text} for s in entry.sections],
            "ask": list(entry.ask),
            "related": [{"id": rid, "title": titles[rid]} for rid in entry.related if rid in titles],
            "kind": entry.kind,
            "link": entry.link,
            "source": entry.source,
            "source_url": entry.source_url,
            "reviewed_at": entry.reviewed_at,
            "review_status": entry.review_status,
        }
```

- [ ] **Step 5: 写加载器**

`services/api/src/aim_api/contexts/guidance/application/queries/get_encyclopedia.py`：

```python
"""加载 content/encyclopedia/ 下的百科文件。

进程内只加载一次：启动时校验（坏内容让启动失败），之后都读内存——
现有内容接口每次请求都重读文件，百科条目多、AIM 会频繁翻目录，不沿用那个做法。

草稿默认不加载。内容审核前绝不能出现在生产环境里，所以开关是「显式打开才有」。
"""

from __future__ import annotations

import os
from dataclasses import replace
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml

from aim_api.contexts.guidance.application.queries.get_guidance import CONTENT_ROOT
from aim_api.contexts.guidance.domain.encyclopedia import (
    TOPICS,
    Encyclopedia,
    EncyclopediaEntry,
    EntrySection,
)

ENCYCLOPEDIA_DIR = "encyclopedia"
INCLUDE_DRAFTS_ENV = "AIM_CONTENT_INCLUDE_DRAFTS"


class EncyclopediaError(Exception):
    """百科文件不合法。"""


def load_encyclopedia(directory: Path, *, include_drafts: bool) -> Encyclopedia:
    if not directory.is_dir():
        return Encyclopedia(entries=())
    known = {topic for topic, _ in TOPICS}
    unknown = sorted(path.stem for path in directory.glob("*.yaml") if path.stem not in known)
    if unknown:
        raise EncyclopediaError(f"unknown encyclopedia topic files: {', '.join(unknown)}")

    entries: list[EncyclopediaEntry] = []
    for topic, _ in TOPICS:
        path = directory / f"{topic}.yaml"
        if not path.is_file():
            continue
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        if str(document.get("review_status", "draft")) != "reviewed" and not include_drafts:
            continue
        try:
            entries.extend(_parse_entry(topic, document, raw) for raw in document["entries"])
        except (KeyError, TypeError, ValueError) as error:
            raise EncyclopediaError(f"{path.name}: {error}") from error

    seen: set[str] = set()
    for entry in entries:
        if entry.id in seen:
            raise EncyclopediaError(f"duplicate encyclopedia entry id: {entry.id}")
        seen.add(entry.id)

    # 已审核的条目可能指向还在草稿里的条目；生产不加载草稿时，丢掉这些链接而不是报错。
    # 内容测试会在「全部加载」时确认每个链接都指向存在的条目。
    return Encyclopedia(
        entries=tuple(
            replace(entry, related=tuple(rid for rid in entry.related if rid in seen))
            for entry in entries
        )
    )


def _parse_entry(topic: str, document: dict[str, Any], raw: dict[str, Any]) -> EncyclopediaEntry:
    entry_id = str(raw["id"])
    if not entry_id.startswith(f"{topic}."):
        raise ValueError(f"entry {entry_id} must start with '{topic}.'")

    weeks = raw.get("weeks")
    parsed_weeks: tuple[int, int] | None = None
    if weeks is not None:
        start, end = (int(week) for week in weeks)
        if not 4 <= start <= end <= 42:
            raise ValueError(f"entry {entry_id} has invalid weeks {weeks}")
        parsed_weeks = (start, end)

    kind = raw.get("kind")
    link = raw.get("link")
    if kind not in (None, "policy"):
        raise ValueError(f"entry {entry_id} has unknown kind {kind}")
    if kind == "policy" and not link:
        raise ValueError(f"policy entry {entry_id} needs a link")

    return EncyclopediaEntry(
        id=entry_id,
        topic=topic,
        title=str(raw["title"]),
        aliases=tuple(str(alias) for alias in raw.get("aliases") or ()),
        weeks=parsed_weeks,
        summary=str(raw["summary"]),
        sections=tuple(
            EntrySection(heading=str(section["heading"]), text=str(section["text"]))
            for section in raw["sections"]
        ),
        ask=tuple(str(question) for question in raw["ask"]),
        related=tuple(str(rid) for rid in raw.get("related") or ()),
        kind=kind,
        link=str(link) if link else None,
        source=str(document["source"]),
        source_url=str(document["source_url"]),
        reviewed_at=str(document["reviewed_at"]) if document.get("reviewed_at") else None,
        review_status=str(document.get("review_status", "draft")),
    )


@lru_cache(maxsize=1)
def get_encyclopedia() -> Encyclopedia:
    return load_encyclopedia(
        CONTENT_ROOT / ENCYCLOPEDIA_DIR,
        include_drafts=os.environ.get(INCLUDE_DRAFTS_ENV) == "1",
    )
```

- [ ] **Step 6: 跑测试确认通过**

Run: `cd services/api && python3 -m pytest tests/application/guidance/test_encyclopedia.py -q`
Expected: 11 passed

- [ ] **Step 7: 架构与 lint**

Run: `cd services/api && python3 -m pytest tests/architecture -q && make lint`
Expected: 通过（领域对象不依赖 yaml / 文件系统）

- [ ] **Step 8: 提交**

```bash
git add content/encyclopedia/schema.json services/api/src/aim_api/contexts/guidance/domain/encyclopedia.py services/api/src/aim_api/contexts/guidance/application/queries/get_encyclopedia.py services/api/tests/application/guidance/test_encyclopedia.py
git commit -m "feat(api): 孕期百科的内容格式、加载与按孕周挑选"
```

---

### Task 2: 百科接口、启动加载与草稿开关

**Files:**
- Modify: `services/api/src/aim_api/contexts/guidance/adapters/inbound/http/router.py`
- Modify: `services/api/src/aim_api/bootstrap.py:55-60`
- Modify: `services/api/tests/conftest.py`（文件顶部 import 之后）
- Modify: `infrastructure/compose/compose.yaml`（`api.environment`）
- Modify: `infrastructure/compose/compose.prod.yaml`（`api`）
- Test: `services/api/tests/integration/test_encyclopedia_api.py`、`services/api/tests/contract/test_deploy_config.py`
- 重新生成：`contracts/public-api/openapi.json`

**Interfaces:**
- Consumes: Task 1 的 `get_encyclopedia()`、`Encyclopedia.catalog/detail`。
- Produces:
  - `GET /api/v1/library/encyclopedia?topic=<str>&week=<int 0–45>` → 目录 JSON（未知主题返回空 `entries`）。不需要登录。
  - `GET /api/v1/library/encyclopedia/{entry_id}` → 详情 JSON；不存在 404。不需要登录。

- [ ] **Step 1: 写失败的测试**

`services/api/tests/integration/test_encyclopedia_api.py`：

```python
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.contexts.guidance.adapters.inbound.http import router as guidance_router
from aim_api.contexts.guidance.domain.encyclopedia import (
    Encyclopedia,
    EncyclopediaEntry,
    EntrySection,
)


def _entry(entry_id: str, weeks: tuple[int, int] | None, related: tuple[str, ...] = ()) -> EncyclopediaEntry:
    return EncyclopediaEntry(
        id=entry_id, topic=entry_id.split(".")[0], title=f"标题{entry_id}", aliases=("别名",),
        weeks=weeks, summary="摘要", sections=(EntrySection("是什么", "正文"),),
        ask=("问题一", "问题二"), related=related, kind=None, link=None,
        source="来源", source_url="https://example.com", reviewed_at="2026-10-09",
        review_status="reviewed",
    )


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch):
    fixture = Encyclopedia(entries=(
        _entry("body.cramp", (20, 36), related=("diet.iron",)),
        _entry("diet.iron", None),
    ))
    # 接口与真实内容文件解耦：内容还是草稿、或正在改写时，接口测试照样稳定。
    monkeypatch.setattr(guidance_router, "get_encyclopedia", lambda: fixture)
    with TestClient(create_app()) as test_client:
        yield test_client


def test_catalog_lists_topics_and_entries(client: TestClient) -> None:
    response = client.get("/api/v1/library/encyclopedia")

    assert response.status_code == 200, response.text
    body = response.json()
    assert [t["id"] for t in body["topics"]] == ["body", "diet"]
    assert [e["id"] for e in body["entries"]] == ["body.cramp", "diet.iron"]
    assert "sections" not in body["entries"][0]


def test_catalog_filters_by_week_and_topic(client: TestClient) -> None:
    by_week = client.get("/api/v1/library/encyclopedia", params={"week": 10}).json()
    by_topic = client.get("/api/v1/library/encyclopedia", params={"topic": "body"}).json()

    assert [e["id"] for e in by_week["entries"]] == ["diet.iron"]
    assert [e["id"] for e in by_topic["entries"]] == ["body.cramp"]


def test_entry_detail_and_missing_entry(client: TestClient) -> None:
    found = client.get("/api/v1/library/encyclopedia/body.cramp")
    missing = client.get("/api/v1/library/encyclopedia/body.nope")

    assert found.status_code == 200, found.text
    assert found.json()["related"] == [{"id": "diet.iron", "title": "标题diet.iron"}]
    assert missing.status_code == 404
```

`services/api/tests/contract/test_deploy_config.py`：

```python
from __future__ import annotations

from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[4]


def test_production_never_serves_draft_content() -> None:
    """生产编排叠加在本地编排之上，本地打开的草稿开关会被继承——必须显式关掉。"""
    prod = yaml.safe_load((ROOT / "infrastructure/compose/compose.prod.yaml").read_text(encoding="utf-8"))
    assert prod["services"]["api"]["environment"]["AIM_CONTENT_INCLUDE_DRAFTS"] == "0"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd services/api && python3 -m pytest tests/integration/test_encyclopedia_api.py tests/contract/test_deploy_config.py -q`
Expected: FAIL（`router` 模块没有 `get_encyclopedia` 属性；prod 文件没有 `environment`）

- [ ] **Step 3: 加接口**

在 `router.py` 顶部 import 区加：

```python
from aim_api.contexts.guidance.application.queries.get_encyclopedia import get_encyclopedia
```

在 `get_content_collection_endpoint` **之前**加：

```python
@router.get("/api/v1/library/encyclopedia")
async def get_encyclopedia_catalog_endpoint(
    topic: str | None = Query(default=None),
    week: int | None = Query(default=None, ge=0, le=45),
):
    """孕期百科目录：主题与条目摘要，不含正文。公开内容，不需要登录。"""
    return get_encyclopedia().catalog(topic=topic, week=week)


@router.get("/api/v1/library/encyclopedia/{entry_id}")
async def get_encyclopedia_entry_endpoint(entry_id: str):
    detail = get_encyclopedia().detail(entry_id)
    if detail is None:
        raise NotFoundError(f"encyclopedia entry not found: {entry_id}")
    return detail
```

- [ ] **Step 4: 启动时加载一次**

`bootstrap.py` 顶部 import：

```python
from aim_api.contexts.guidance.application.queries.get_encyclopedia import get_encyclopedia
```

`create_app` 里 `resolved_settings = ...` 之后加：

```python
    # 百科内容有问题时让进程起不来，而不是等第一个请求才 500。
    get_encyclopedia()
```

- [ ] **Step 5: 测试进程打开草稿开关**

`services/api/tests/conftest.py` 在 `import os` 之后、其它 import 之前加：

```python
# 百科内容审核前都是草稿；测试要能读到它们。必须早于任何 create_app()，
# 因为 get_encyclopedia() 进程内只加载一次。
os.environ.setdefault("AIM_CONTENT_INCLUDE_DRAFTS", "1")
```

- [ ] **Step 6: 编排**

`infrastructure/compose/compose.yaml` 的 `api.environment` 里，`AIM_CONTENT_ROOT` 下一行加：

```yaml
      # 本地与模拟器能看到草稿百科；生产在 compose.prod.yaml 里显式关掉。
      AIM_CONTENT_INCLUDE_DRAFTS: ${AIM_CONTENT_INCLUDE_DRAFTS:-1}
```

`infrastructure/compose/compose.prod.yaml` 的 `api:` 下、`restart` 之后加：

```yaml
    environment:
      # 未审核的百科绝不上生产。
      AIM_CONTENT_INCLUDE_DRAFTS: "0"
```

- [ ] **Step 7: 跑测试确认通过，并重新生成契约**

Run: `cd services/api && python3 -m pytest tests/integration/test_encyclopedia_api.py tests/contract -q && make contracts && git diff --stat ../../contracts`
Expected: 测试通过；`contracts/public-api/openapi.json` 多出两个 `/api/v1/library/encyclopedia` 路径

- [ ] **Step 8: 全量 API 测试**

Run: `cd services/api && make test`
Expected: 全部通过（需要本地 `make dev` 的 Postgres 在 55434）

- [ ] **Step 9: 提交**

```bash
git add services/api infrastructure/compose contracts/public-api/openapi.json
git commit -m "feat(api): 孕期百科目录与条目接口；草稿只在本地加载"
```

---

### Task 3: 首批百科内容（约 60 条草稿）

**Files:**
- Create: `content/encyclopedia/checkup.yaml`、`body.yaml`、`diet.yaml`、`life.yaml`、`birth.yaml`、`paperwork.yaml`
- Test: `services/api/tests/contract/content/test_encyclopedia_content.py`

**Interfaces:**
- Consumes: Task 1 的 `schema.json`、`load_encyclopedia`。
- Produces: `diet.yaml` 必须包含由 `content/nutrition/dietary-basics.yaml` 迁来的 7 条，编号为 `diet.<原 id>`（`diet.raw-and-undercooked`、`diet.unpasteurized-dairy`、`diet.high-mercury-fish`、`diet.alcohol`、`diet.caffeine`、`diet.iron-and-folate`、`diet.food-safety-habits`），标题与原条目一致（Task 5 的 UI 用例依赖 `diet.raw-and-undercooked` 标题「生食与未煮熟的食物」）。

- [ ] **Step 1: 写内容测试（先失败）**

`services/api/tests/contract/content/test_encyclopedia_content.py`：

```python
from __future__ import annotations

import json
from pathlib import Path

import pytest
import yaml
from jsonschema import Draft202012Validator

from aim_api.contexts.guidance.application.queries.get_encyclopedia import load_encyclopedia
from aim_api.contexts.guidance.domain.encyclopedia import TOPICS

ROOT = Path(__file__).resolve().parents[5]
DIRECTORY = ROOT / "content/encyclopedia"
DOCUMENTS = sorted(DIRECTORY.glob("*.yaml"))


@pytest.mark.parametrize("document_path", DOCUMENTS, ids=lambda p: p.name)
def test_encyclopedia_document_matches_schema(document_path: Path) -> None:
    schema = json.loads((DIRECTORY / "schema.json").read_text(encoding="utf-8"))
    document = yaml.safe_load(document_path.read_text(encoding="utf-8"))
    errors = sorted(Draft202012Validator(schema).iter_errors(document), key=lambda e: list(e.path))
    assert errors == [], "\n".join(f"{list(e.path)}: {e.message}" for e in errors)


def test_every_topic_has_a_document() -> None:
    assert {path.stem for path in DOCUMENTS} == {topic for topic, _ in TOPICS}


def test_related_links_point_to_existing_entries() -> None:
    raw_ids: set[str] = set()
    raw_related: list[tuple[str, str]] = []
    for path in DOCUMENTS:
        for entry in yaml.safe_load(path.read_text(encoding="utf-8"))["entries"]:
            raw_ids.add(entry["id"])
            raw_related.extend((entry["id"], rid) for rid in entry.get("related", []))
    dangling = [(source, target) for source, target in raw_related if target not in raw_ids]
    assert dangling == []


def test_all_content_loads_together() -> None:
    encyclopedia = load_encyclopedia(DIRECTORY, include_drafts=True)
    assert len(encyclopedia.entries) >= 55


def test_every_week_has_at_least_two_entries() -> None:
    """只检查已审核的内容：草稿阶段的覆盖率不代表上线后的样子。"""
    published = load_encyclopedia(DIRECTORY, include_drafts=False)
    if not published.entries:
        pytest.skip("还没有审核通过的百科文件")
    thin = [
        week for week in range(4, 41)
        if sum(1 for e in published.entries if e.weeks and e.covers(week)) < 2
    ]
    assert thin == []


def test_drafts_cover_every_week_too() -> None:
    """草稿也要满足覆盖要求——否则审核通过的那天才发现缺口。"""
    everything = load_encyclopedia(DIRECTORY, include_drafts=True)
    thin = [
        week for week in range(4, 41)
        if sum(1 for e in everything.entries if e.weeks and e.covers(week)) < 2
    ]
    assert thin == []


def test_nutrition_basics_moved_into_diet() -> None:
    old = yaml.safe_load((ROOT / "content/nutrition/dietary-basics.yaml").read_text(encoding="utf-8"))
    encyclopedia = load_encyclopedia(DIRECTORY, include_drafts=True)
    for item in old["items"]:
        entry = encyclopedia.get(f"diet.{item['id']}")
        assert entry is not None, item["id"]
        assert entry.title == item["title"]
```

Run: `cd services/api && python3 -m pytest tests/contract/content/test_encyclopedia_content.py -q`
Expected: FAIL（没有任何 yaml）

- [ ] **Step 2: 起草六个文件**

每个文件头：

```yaml
id: encyclopedia-<主题>
version: 0.1.0
source: 中华医学会妇产科学分会《孕前和孕期保健指南（2018）》；中国营养学会《中国居民膳食指南（2022）》孕期妇女膳食指南；国家卫生健康委员会公开的孕产期保健资料
source_url: https://www.nhc.gov.cn/
reviewed_at: null
review_status: draft
entries:
```

（`paperwork.yaml` 的 `source` 改为「杭州市及浙江省政府公开的办事指南」，`source_url` 用 `https://www.hangzhou.gov.cn/`。）

条目数量与覆盖（总数 ≥55）：

| 文件 | 数量 | 必须包含的条目（编号短名可自定，标题按此） |
| --- | --- | --- |
| `checkup.yaml` | 14 | 早孕检查与建档、NT 检查、早期唐筛、无创 DNA、中期唐筛、大排畸、糖耐量、胎心监护、B 超的意义、血常规与贫血、尿常规、甲功、羊水穿刺、产检时间表（全程） |
| `body.yaml` | 14 | 孕吐、乏力嗜睡、尿频、便秘、腰酸背痛、腿抽筋、水肿、妊娠纹与皮肤瘙痒、失眠、胃灼热、**胎动与数胎动**（编号固定为 `body.fetal-movement`，`weeks: [16, 40]`，必须讲清何时开始感到胎动、28 周起怎么数、什么情况立即就医；胎动计数功能会链接它）、假性宫缩与真宫缩、阴道分泌物变化、情绪波动 |
| `diet.yaml` | 12 | 迁入的 7 条 + 孕期体重增长、补钙、补碘、孕期控糖饮食、孕吐期怎么吃 |
| `life.yaml` | 8 | 孕期运动、出行与乘车、上班与久坐、性生活、用药原则、口腔护理、宠物与弓形虫、睡姿 |
| `birth.yaml` | 8 | 产兆（见红、破水、规律宫缩）、什么时候去医院、顺产与剖宫产、无痛分娩、待产包准备、分娩前的身体准备、过了预产期、产后第一天 |
| `paperwork.yaml` | 4 | 建档建册、生育津贴、陪产假与产假、出生「一件事」联办；全部 `kind: policy` + `link`（官方入口，如浙里办或杭州市医保局页面） |

`weeks` 安排：除少数全程条目外都给出适用孕周，使第 4–40 周每周至少有 2 条覆盖（`test_drafts_cover_every_week_too` 守住）。

写作约束（审核者会按此检查）：
- 平实、不吓人、不诊断。剂量、检查时间写「按医生安排」，或写指南里的常见范围并注明「以医生意见为准」。
- 凡涉及症状的条目，`sections` 里必须有一段 `heading: 什么时候找医生`。
- 政策类正文不写金额、资格、天数等结论，只说明「去哪里查、要准备什么材料」，结论交给 `link`。
- `aliases` 写用户的口语说法（如糖耐量：「喝糖水」「OGTT」「糖筛」）。
- `ask` 写用户真会问的问题，≤24 字。
- `related` 只连本批次里存在的编号（示例里的 `life.pets-and-toxoplasma` 也要真实存在）。

示例（`diet.yaml` 迁入条目的写法）：

```yaml
  - id: diet.raw-and-undercooked
    title: 生食与未煮熟的食物
    aliases: [生鱼片, 溏心蛋, 半熟牛排, 刺身]
    summary: 生鱼片、溏心蛋、未煮熟的肉类存在李斯特菌与寄生虫风险，孕期建议彻底做熟。
    sections:
      - heading: 为什么
        text: 孕期免疫状态变化，李斯特菌、弓形虫等感染的风险和后果都比平时更大。彻底加热能杀灭它们。
      - heading: 怎么做
        text: 肉类做到中心没有血色，鸡蛋煮到蛋黄凝固，海鲜彻底熟透。外出就餐时主动说明要全熟。
      - heading: 什么时候找医生
        text: 吃过可疑食物后出现发热、肌肉酸痛、腹泻等类似感冒的症状，及时就医并说明饮食情况。
    ask: [吃了溏心蛋要紧吗, 寿司里哪些能吃, 外卖怎么点更安全]
    related: [diet.food-safety-habits, life.pets-and-toxoplasma]
```

- [ ] **Step 3: 跑内容测试直到通过**

Run: `cd services/api && python3 -m pytest tests/contract/content/test_encyclopedia_content.py -q`
Expected: 全部通过（`test_every_week_has_at_least_two_entries` 显示 skipped）

- [ ] **Step 4: 确认本地栈能读到**

Run: `make dev`（另一个终端，重建镜像），然后 `curl -s 'http://127.0.0.1:8100/api/v1/library/encyclopedia?week=25' | python3 -m json.tool | head -40`
Expected: `topics` 有六个主题，`entries` 非空

- [ ] **Step 5: 提交**

```bash
git add content/encyclopedia services/api/tests/contract/content/test_encyclopedia_content.py
git commit -m "content: 孕期百科首批草稿（六个主题）；饮食基线并入百科"
```

---

### Task 4: iOS 百科数据层

**Files:**
- Create: `apps/ios/AimApp/Features/Library/EncyclopediaModels.swift`
- Modify: `apps/ios/AimApp/Clients/BusinessAPIClient/BusinessRepository.swift`（协议、默认实现扩展、`BusinessRepository` actor）
- Modify: `apps/ios/AimApp/Features/Library/LibraryStore.swift`
- Modify: `apps/ios/AimApp/Features/Library/LibraryCatalog.swift`（`LibrarySnapshot`、`.nutrition` 摘要）
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`
- Test: `apps/ios/AimApp/Tests/EncyclopediaCatalogTests.swift`，必要时 `Tests/LibraryCatalogTests.swift`

**Interfaces:**
- Consumes: Task 2 的两个接口与 JSON 形状。
- Produces（Task 5 依赖）：
  - `EncyclopediaTopic { id, name, count, icon }`（`Hashable`）
  - `EncyclopediaEntrySummary { id, topic, title, aliases, weeks: [Int]?, summary, weeksLabel: String?, covers(week:) -> Bool, isTimely(week:) -> Bool }`
  - `EncyclopediaCatalog { topics, entries, isEmpty, picks(forWeek:limit:), entries(inTopic:week:), timelyCount(topic:week:) }`
  - `EncyclopediaEntry { id, topic, title, weeks, weeksLabel, summary, sections: [Section], ask, related: [Related], kind, link, source, sourceURL, reviewedAt, reviewStatus, isPolicy, isDraft }`
  - `BusinessRepositoryProtocol.fetchEncyclopediaCatalog() async throws -> EncyclopediaCatalog`、`fetchEncyclopediaEntry(id: String) async throws -> EncyclopediaEntry`
  - `LibraryStore.encyclopedia: EncyclopediaCatalog`、`LibraryStore.currentWeek: Int?`、`LibraryStore.entry(id:) async throws -> EncyclopediaEntry`
  - `LibrarySnapshot.encyclopediaCounts: [String: Int]`

- [ ] **Step 1: 写失败的测试**

`apps/ios/AimApp/Tests/EncyclopediaCatalogTests.swift`：

```swift
import XCTest
@testable import AimApp

final class EncyclopediaCatalogTests: XCTestCase {
    private func summary(_ id: String, weeks: [Int]?) -> EncyclopediaEntrySummary {
        EncyclopediaEntrySummary(
            id: id, topic: String(id.split(separator: ".")[0]), title: id,
            aliases: [], weeks: weeks, summary: "摘要")
    }

    private var catalog: EncyclopediaCatalog {
        EncyclopediaCatalog(
            topics: [EncyclopediaTopic(id: "body", name: "身体变化与不适", count: 4)],
            entries: [
                summary("body.early", weeks: [4, 12]),
                summary("body.mid", weeks: [20, 30]),
                summary("body.always", weeks: nil),
                summary("body.now", weeks: [24, 28]),
            ])
    }

    /// 全程适用的条目每周都会出现，放进「这周读什么」等于没推荐。
    func testWeeklyPicksSkipWholePregnancyEntriesAndRankByClosestStart() {
        XCTAssertEqual(catalog.picks(forWeek: 25).map(\.id), ["body.now", "body.mid"])
        XCTAssertEqual(catalog.picks(forWeek: 25, limit: 1).map(\.id), ["body.now"])
        XCTAssertEqual(catalog.picks(forWeek: 40).map(\.id), [])
    }

    func testTopicPageListsTimelyEntriesFirstThenKeepsFileOrder() {
        XCTAssertEqual(
            catalog.entries(inTopic: "body", week: 25).map(\.id),
            ["body.mid", "body.now", "body.early", "body.always"])
        XCTAssertEqual(
            catalog.entries(inTopic: "body", week: nil).map(\.id),
            ["body.early", "body.mid", "body.always", "body.now"])
    }

    func testTimelyCountIgnoresWholePregnancyEntries() {
        XCTAssertEqual(catalog.timelyCount(topic: "body", week: 25), 2)
        XCTAssertEqual(catalog.timelyCount(topic: "body", week: nil), 0)
    }

    func testWeeksLabel() {
        XCTAssertEqual(summary("a.b", weeks: [24, 28]).weeksLabel, "孕 24–28 周")
        XCTAssertEqual(summary("a.b", weeks: [12, 12]).weeksLabel, "孕 12 周")
        XCTAssertNil(summary("a.b", weeks: nil).weeksLabel)
    }

    func testDecodesEntryDetailFromTheAPIShape() throws {
        let json = """
        {"id":"paperwork.allowance","topic":"paperwork","title":"生育津贴","aliases":[],
         "weeks":null,"summary":"摘要","sections":[{"heading":"去哪办","text":"正文"}],
         "ask":["要带什么材料","多久能到账"],"related":[{"id":"paperwork.leave","title":"产假"}],
         "kind":"policy","link":"https://example.com","source":"来源",
         "source_url":"https://example.com","reviewed_at":null,"review_status":"draft"}
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(EncyclopediaEntry.self, from: json)

        XCTAssertTrue(entry.isPolicy)
        XCTAssertTrue(entry.isDraft)
        XCTAssertEqual(entry.related.first?.title, "产假")
        XCTAssertEqual(entry.sections.first?.heading, "去哪办")
        XCTAssertNil(entry.weeksLabel)
    }

    func testDecodesCatalogFromTheAPIShape() throws {
        let json = """
        {"topics":[{"id":"diet","name":"饮食营养","count":1}],
         "entries":[{"id":"diet.iron","topic":"diet","title":"补铁","aliases":["贫血"],"weeks":[13,40],"summary":"摘要"}]}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(EncyclopediaCatalog.self, from: json)

        XCTAssertEqual(decoded.topics.first?.icon, "fork.knife")
        XCTAssertEqual(decoded.entries.first?.weeks, [13, 40])
    }
}
```

在 `project.pbxproj` 登记 `Tests/EncyclopediaCatalogTests.swift`（编号 `A10000000000000000000159` / `A20000000000000000000159`，照抄 `Tests/HomeDashboardTests.swift` 的四处）。

- [ ] **Step 2: 跑测试确认失败**

Run: `make ios-test IOS_DESTINATION='platform=iOS Simulator,name=iPhone 18 Pro' 2>&1 | grep -E "error:|EncyclopediaCatalogTests" | head`
Expected: 编译失败，`cannot find 'EncyclopediaCatalog' in scope`

- [ ] **Step 3: 写模型**

`apps/ios/AimApp/Features/Library/EncyclopediaModels.swift`（登记编号 `…155`，照抄 `Features/Home/WeeklyContent.swift` 的四处）：

```swift
import Foundation

/// 孕期百科：经人工审核、随内容发布的孕期知识，按主题与孕周组织。
/// 目录一次整份拉取（约 60 条摘要），挑选与排序在本地做；正文按需拉取。
struct EncyclopediaTopic: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let count: Int

    /// 图标是客户端的事，服务端只给主题编号。
    var icon: String {
        switch id {
        case "checkup": "stethoscope"
        case "body": "figure.stand"
        case "diet": "fork.knife"
        case "life": "figure.walk"
        case "birth": "suitcase"
        case "paperwork": "doc.text"
        default: "book"
        }
    }
}

func encyclopediaWeeksLabel(_ weeks: [Int]?) -> String? {
    guard let weeks, weeks.count == 2 else { return nil }
    return weeks[0] == weeks[1] ? "孕 \(weeks[0]) 周" : "孕 \(weeks[0])–\(weeks[1]) 周"
}

struct EncyclopediaEntrySummary: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let topic: String
    let title: String
    let aliases: [String]
    /// `[起, 止]`；`nil` 表示全程适用。
    let weeks: [Int]?
    let summary: String

    var weeksLabel: String? { encyclopediaWeeksLabel(weeks) }

    func covers(week: Int) -> Bool {
        guard let weeks, weeks.count == 2 else { return true }
        return weeks[0] <= week && week <= weeks[1]
    }

    /// 标了孕周且覆盖本周。全程适用的条目不算「当下」——它们每周都在。
    func isTimely(week: Int?) -> Bool {
        guard let week, weeks != nil else { return false }
        return covers(week: week)
    }
}

struct EncyclopediaCatalog: Decodable, Equatable, Sendable {
    var topics: [EncyclopediaTopic] = []
    var entries: [EncyclopediaEntrySummary] = []

    var isEmpty: Bool { entries.isEmpty }

    /// 「这周读什么」：适用期起点离本周越近越靠前——刚进入适用期的内容最值得现在读。
    func picks(forWeek week: Int, limit: Int = 5) -> [EncyclopediaEntrySummary] {
        entries.enumerated()
            .filter { $0.element.isTimely(week: week) }
            .sorted { lhs, rhs in
                let l = abs(week - (lhs.element.weeks?.first ?? week))
                let r = abs(week - (rhs.element.weeks?.first ?? week))
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .prefix(limit)
            .map(\.element)
    }

    /// 主题页：本周相关的排前面，其余保持内容文件里的顺序。
    func entries(inTopic topic: String, week: Int?) -> [EncyclopediaEntrySummary] {
        let inTopic = entries.filter { $0.topic == topic }
        return inTopic.filter { $0.isTimely(week: week) } + inTopic.filter { !$0.isTimely(week: week) }
    }

    func timelyCount(topic: String, week: Int?) -> Int {
        entries.filter { $0.topic == topic && $0.isTimely(week: week) }.count
    }
}

struct EncyclopediaEntry: Decodable, Equatable, Sendable, Identifiable {
    struct Section: Decodable, Equatable, Sendable {
        let heading: String
        let text: String
    }

    struct Related: Decodable, Equatable, Sendable, Identifiable {
        let id: String
        let title: String
    }

    let id: String
    let topic: String
    let title: String
    let weeks: [Int]?
    let summary: String
    let sections: [Section]
    let ask: [String]
    let related: [Related]
    let kind: String?
    let link: String?
    let source: String
    let sourceURL: String
    let reviewedAt: String?
    let reviewStatus: String

    var weeksLabel: String? { encyclopediaWeeksLabel(weeks) }
    /// 政策类：App 不下结论，只给官方核对入口。
    var isPolicy: Bool { kind == "policy" }
    var isDraft: Bool { reviewStatus != "reviewed" }

    enum CodingKeys: String, CodingKey {
        case id, topic, title, weeks, summary, sections, ask, related, kind, link, source
        case sourceURL = "source_url"
        case reviewedAt = "reviewed_at"
        case reviewStatus = "review_status"
    }
}
```

- [ ] **Step 4: 仓储**

`BusinessRepositoryProtocol` 末尾（`fetchWeeklyContent()` 之后）加：

```swift
    func fetchEncyclopediaCatalog() async throws -> EncyclopediaCatalog
    func fetchEncyclopediaEntry(id: String) async throws -> EncyclopediaEntry
```

协议的默认实现扩展末尾加（测试替身不必逐个补齐）：

```swift
    func fetchEncyclopediaCatalog() async throws -> EncyclopediaCatalog { throw APIError.notConfigured }
    func fetchEncyclopediaEntry(id: String) async throws -> EncyclopediaEntry { throw APIError.notConfigured }
```

`BusinessRepository` actor 里 `fetchWeeklyContent()` 之后加：

```swift
    /// 孕期百科目录。公开内容，不需要登录。
    func fetchEncyclopediaCatalog() async throws -> EncyclopediaCatalog {
        let (data, _) = try await session.aimData(
            for: environment.businessRequest(path: "/api/v1/library/encyclopedia"))
        return try JSONDecoder().decode(EncyclopediaCatalog.self, from: data)
    }

    func fetchEncyclopediaEntry(id: String) async throws -> EncyclopediaEntry {
        let (data, _) = try await session.aimData(
            for: environment.businessRequest(path: "/api/v1/library/encyclopedia/\(id)"))
        return try JSONDecoder().decode(EncyclopediaEntry.self, from: data)
    }
```

- [ ] **Step 5: LibraryStore 与快照**

`LibraryCatalog.swift` 的 `LibrarySnapshot` 加字段：

```swift
    /// 百科各主题的条目数。「吃什么」没有用户条目时用饮食主题的数量做摘要。
    var encyclopediaCounts: [String: Int] = [:]
```

`.nutrition` 摘要改为：

```swift
        case .nutrition:
            guard let total = snapshot.encyclopediaCounts["diet"], total > 0 else {
                return LibrarySummary(headline: Self.placeholderHeadline(for: self))
            }
            return LibrarySummary(headline: "\(total) 条饮食提示")
```

`LibraryStore`：

```swift
    var encyclopedia = EncyclopediaCatalog()
    /// 当前孕周。「这周读什么」与主题页的「本周」标记靠它；取不到时这两处不显示。
    var currentWeek: Int?
    private var entryCache: [String: EncyclopediaEntry] = [:]
```

`load()` 里：删除 `async let nutrition = …` 及其在元组、`collections` 字典里的位置（`collections` 只剩 `hangzhou`、`preparation`）；在 `do {` 内、`let loaded = try await …` 之前加：

```swift
            // 百科与孕周取不到不该让整个资料库打不开：它们缺席时对应区块不显示即可。
            async let catalog = try? repository.fetchEncyclopediaCatalog()
            async let pregnancy = try? repository.fetchPregnancy()
```

`snapshot = LibrarySnapshot(...)` 之前加：

```swift
            if let fetched = await catalog { encyclopedia = fetched }
            if let fetched = await pregnancy { currentWeek = fetched?.weeks }
```

`LibrarySnapshot(...)` 构造补上 `encyclopediaCounts: Dictionary(uniqueKeysWithValues: encyclopedia.topics.map { ($0.id, $0.count) })`。

新增：

```swift
    /// 百科正文。同一次运行里看过的条目不重复拉取。
    func entry(id: String) async throws -> EncyclopediaEntry {
        if let cached = entryCache[id] { return cached }
        guard let repository else { throw APIError.notConfigured }
        let fetched = try await repository.fetchEncyclopediaEntry(id: id)
        entryCache[id] = fetched
        return fetched
    }
```

- [ ] **Step 6: 修 LibraryCatalogTests 中依赖 `collectionSizes["nutrition"]` 的断言**

Run: `grep -n 'nutrition' apps/ios/AimApp/Tests/LibraryCatalogTests.swift`
若有用 `collectionSizes: ["nutrition": N]` 断言「N 条饮食提示」的用例，改为 `encyclopediaCounts: ["diet": N]`，断言文字不变。

- [ ] **Step 7: 跑测试确认通过**

Run: `make ios-test IOS_DESTINATION='platform=iOS Simulator,name=iPhone 18 Pro' 2>&1 | grep -E "Test Suite 'All tests'|failed|error:" | head -20`
Expected: `EncyclopediaCatalogTests`、`LibraryCatalogTests`、`LibraryStoreTests` 全部通过（UI 用例中两条既有失败与本任务无关）

- [ ] **Step 8: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): 孕期百科的数据模型、接口与资料库加载；吃什么摘要改读百科"
```

---

### Task 5: iOS 百科界面

**Files:**
- Create: `apps/ios/AimApp/Features/Library/EncyclopediaSections.swift`（`…156`）
- Create: `apps/ios/AimApp/Features/Library/EncyclopediaTopicView.swift`（`…157`）
- Create: `apps/ios/AimApp/Features/Library/EncyclopediaEntryView.swift`（`…158`）
- Modify: `apps/ios/AimApp/Features/Library/LibraryView.swift`
- Modify: `apps/ios/AimApp/Features/Library/LibraryCategoryDetail.swift:535-543`（「Aim 自带的参考」）
- Modify: `apps/ios/AimApp.xcodeproj/project.pbxproj`
- Test: `apps/ios/AimApp/UITests/CoreJourneyUITests.swift`

**Interfaces:**
- Consumes: Task 4 的模型、`LibraryStore.encyclopedia/currentWeek/entry(id:)`；`AgentStore.prepareAnalysis(_:context:)`、`AgentView(store:onClose:)`。
- Produces（无障碍标识，UI 用例依赖）：`library-weekly-picks`、`library-pick-<id>`、`library-section-archive`、`library-section-encyclopedia`、`library-topic-<topic>`、`encyclopedia-entry-<id>`、`encyclopedia-ask-<序号>`、`encyclopedia-policy-link`、`encyclopedia-related-<id>`。

- [ ] **Step 1: 写失败的 UI 用例**

在 `CoreJourneyUITests.swift` 加：

```swift
    /// 百科是资料库「开箱就有内容」的那一层：主题 → 条目 → 顺着条目问 AIM。
    func testEncyclopediaTopicEntryAndAskAIM() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset-session"]
        app.launch()

        registerNewAccount(in: app)
        completePregnancySetup(in: app)

        let libraryTab = app.tabBars.buttons["资料库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 15))
        libraryTab.tap()

        XCTAssertTrue(app.otherElements["library-weekly-picks"].waitForExistence(timeout: 10),
                      "有当前孕周时应当显示「这周读什么」")

        let topic = app.buttons["library-topic-diet"]
        reveal(topic, in: app)
        topic.tap()

        let entry = app.buttons["encyclopedia-entry-diet.raw-and-undercooked"]
        reveal(entry, in: app)
        entry.tap()

        XCTAssertTrue(app.navigationBars["生食与未煮熟的食物"].waitForExistence(timeout: 10))
        let ask = app.buttons["encyclopedia-ask-0"]
        reveal(ask, in: app)
        ask.tap()

        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15),
                      "点推荐问题应当打开 AIM")
    }
```

把既有用例里「饮食提示 → `content-item-raw-and-undercooked`」那段（约 411–429 行）改为：

```swift
        // 饮食提示下列出的是百科「饮食营养」主题的条目。
        let item = app.buttons["encyclopedia-entry-diet.raw-and-undercooked"]
        reveal(item, in: app)
        item.tap()

        XCTAssertTrue(
            app.navigationBars["生食与未煮熟的食物"].waitForExistence(timeout: 10),
            "百科条目应当能点进详情"
        )
        XCTAssertTrue(
            app.buttons["encyclopedia-ask-0"].waitForExistence(timeout: 5),
            "详情里应当能就这条问 AIM"
        )
```

- [ ] **Step 2: 写条目详情**

`EncyclopediaEntryView.swift`：

```swift
import SwiftUI

/// 百科条目详情。正文按需拉取；推荐问题点一下就带着这条去问 AIM 并直接发出。
struct EncyclopediaEntryView: View {
    let entryID: String
    let store: LibraryStore
    let agentStore: AgentStore

    @State private var entry: EncyclopediaEntry?
    @State private var failed = false
    @State private var showingAgent = false

    var body: some View {
        Group {
            if let entry {
                content(entry)
            } else if failed {
                AimErrorState(message: "这条资料暂时打不开") { Task { await load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.aimCanvas)
        .navigationTitle(entry?.title ?? "")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task(id: entryID) { await load() }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
    }

    private func load() async {
        failed = false
        do { entry = try await store.entry(id: entryID) } catch { failed = true }
    }

    private func content(_ entry: EncyclopediaEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AimMetrics.space12) {
                HStack(spacing: AimMetrics.space8) {
                    if let name = store.encyclopedia.topics.first(where: { $0.id == entry.topic })?.name {
                        tag(name)
                    }
                    if let weeks = entry.weeksLabel { tag(weeks) }
                }
                Text(entry.summary)
                    .font(.body)
                    .foregroundStyle(Color.aimTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(entry.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: AimMetrics.space8) {
                        Text(section.heading).font(.headline).foregroundStyle(Color.aimTextPrimary)
                        Text(section.text)
                            .font(.subheadline)
                            .foregroundStyle(Color.aimTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .aimCard()
                }

                if entry.isPolicy, let link = entry.link.flatMap(URL.init(string:)) {
                    Link(destination: link) {
                        Label("到官方渠道核对", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .aimCard()
                    .accessibilityIdentifier("encyclopedia-policy-link")
                }

                askCard(entry)

                if !entry.related.isEmpty {
                    VStack(alignment: .leading, spacing: AimMetrics.space8) {
                        Text("相关").font(.headline).foregroundStyle(Color.aimTextPrimary)
                        ForEach(entry.related) { related in
                            NavigationLink {
                                EncyclopediaEntryView(entryID: related.id, store: store, agentStore: agentStore)
                            } label: {
                                HStack {
                                    Text(related.title).font(.subheadline).foregroundStyle(Color.aimTextPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.aimTextTertiary)
                                }
                            }
                            .accessibilityIdentifier("encyclopedia-related-\(related.id)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .aimCard()
                }

                Text(footer(entry))
                    .font(.caption2)
                    .foregroundStyle(Color.aimTextTertiary)
                    .padding(.horizontal, AimMetrics.space4)
            }
            .padding(.horizontal, AimMetrics.space16)
            .padding(.bottom, AimMetrics.space28)
        }
    }

    private func askCard(_ entry: EncyclopediaEntry) -> some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Label("问问 AIM", systemImage: "wand.and.sparkles")
                .font(.headline)
                .foregroundStyle(Color.aimAccent)
            ForEach(Array(entry.ask.enumerated()), id: \.offset) { index, question in
                Button {
                    agentStore.prepareAnalysis(question, context: AgentContext(
                        title: "百科：\(entry.title)",
                        summary: "条目编号 \(entry.id)\n\(entry.summary)"))
                    showingAgent = true
                } label: {
                    HStack {
                        Text(question).font(.subheadline).foregroundStyle(Color.aimTextPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(Color.aimAccent)
                    }
                    .padding(.vertical, AimMetrics.space4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("encyclopedia-ask-\(index)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aimCard()
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, AimMetrics.space8)
            .padding(.vertical, 2)
            .background(Color.aimAccentSoft, in: Capsule())
            .foregroundStyle(Color.aimAccent)
    }

    private func footer(_ entry: EncyclopediaEntry) -> String {
        let review = entry.isDraft ? "草稿，尚未审核" : "\(entry.reviewedAt ?? "") 核对"
        let policy = entry.isPolicy ? "政策以官方最新规定为准。" : "具体情况以产检医生的意见为准。"
        return "来源：\(entry.source)。\(review)。\(policy)"
    }
}
```

先确认 `AimErrorState` 的初始化参数：Run `sed -n 24,45p apps/ios/AimApp/Core/DesignSystem/Components/AimStateViews.swift`，按其实际签名调整上面那一行。

- [ ] **Step 3: 写主题页与通用条目行**

`EncyclopediaTopicView.swift`：

```swift
import SwiftUI

/// 一个百科主题下的全部条目。本周相关的排前面并标出来。
struct EncyclopediaTopicView: View {
    let topic: EncyclopediaTopic
    let store: LibraryStore
    let agentStore: AgentStore

    var body: some View {
        List {
            ForEach(store.encyclopedia.entries(inTopic: topic.id, week: store.currentWeek)) { entry in
                NavigationLink {
                    EncyclopediaEntryView(entryID: entry.id, store: store, agentStore: agentStore)
                } label: {
                    EncyclopediaEntryRow(entry: entry, week: store.currentWeek)
                }
                .accessibilityIdentifier("encyclopedia-entry-\(entry.id)")
                .listRowBackground(Color.aimSurface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.aimCanvas)
        .navigationTitle(topic.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

/// 百科条目在列表里的一行。主题页与「吃什么 · 饮食提示」共用。
struct EncyclopediaEntryRow: View {
    let entry: EncyclopediaEntrySummary
    let week: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AimMetrics.space8) {
                if entry.isTimely(week: week) {
                    Text("本周")
                        .font(.caption2)
                        .padding(.horizontal, AimMetrics.space8)
                        .padding(.vertical, 1)
                        .background(Color.aimAccentSoft, in: Capsule())
                        .foregroundStyle(Color.aimAccent)
                }
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.aimTextPrimary)
            }
            Text(entry.summary)
                .font(.footnote)
                .foregroundStyle(Color.aimTextSecondary)
                .lineLimit(2)
        }
    }
}
```

- [ ] **Step 4: 写资料库首页的两个新区块**

`EncyclopediaSections.swift`：

```swift
import SwiftUI

/// 资料库首页的「这周读什么」：横向滑动的卡片，取覆盖本周的百科条目。
/// 这是资料库随孕期变化的主要位置——不同孕周打开看到的不一样。
struct EncyclopediaWeeklyPicks: View {
    let week: Int
    let picks: [EncyclopediaEntrySummary]
    let topics: [EncyclopediaTopic]
    let open: (EncyclopediaEntrySummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Text("孕 \(week) 周，这周读什么")
                .font(.headline)
                .foregroundStyle(Color.aimTextPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: AimMetrics.space12) {
                    ForEach(picks) { entry in
                        Button { open(entry) } label: { card(entry) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("library-pick-\(entry.id)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-weekly-picks")
    }

    private func card(_ entry: EncyclopediaEntrySummary) -> some View {
        let topic = topics.first { $0.id == entry.topic }
        return VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Label(topic?.name ?? "", systemImage: topic?.icon ?? "book")
                .font(.caption2)
                .foregroundStyle(Color.aimAccent)
            Text(entry.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.aimTextPrimary)
                .lineLimit(1)
            Text(entry.summary)
                .font(.caption)
                .foregroundStyle(Color.aimTextSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(width: 200, height: 120, alignment: .topLeading)
        .aimCard()
    }
}

/// 资料库首页的「孕期百科」：六个主题卡。
struct EncyclopediaTopicGrid: View {
    let catalog: EncyclopediaCatalog
    let week: Int?
    let open: (EncyclopediaTopic) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: AimMetrics.space12),
        GridItem(.flexible(), spacing: AimMetrics.space12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: AimMetrics.space12) {
            ForEach(catalog.topics) { topic in
                Button { open(topic) } label: { card(topic) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-topic-\(topic.id)")
            }
        }
    }

    private func card(_ topic: EncyclopediaTopic) -> some View {
        let timely = catalog.timelyCount(topic: topic.id, week: week)
        return VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Image(systemName: topic.icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.aimAccent)
            Text(topic.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.aimTextPrimary)
            Text(timely > 0 ? "\(topic.count) 条 · 本周相关 \(timely)" : "\(topic.count) 条")
                .font(.caption)
                .foregroundStyle(Color.aimTextSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .aimCard()
    }
}
```

- [ ] **Step 5: 改资料库首页**

`LibraryView`：

1. 加状态：

```swift
    @State private var openTopic: EncyclopediaTopic?
    @State private var openEntryID: String?
```

2. `VStack` 内容改为（`header` 之后）：

```swift
                    header
                    if let week = store.currentWeek {
                        let picks = store.encyclopedia.picks(forWeek: week)
                        if !picks.isEmpty {
                            EncyclopediaWeeklyPicks(
                                week: week, picks: picks, topics: store.encyclopedia.topics
                            ) { openEntryID = $0.id }
                        }
                    }
                    if let focus = LibraryFocus.make(from: store.snapshot) {
                        LibraryFocusBanner(focus: focus)
                    }
                    sectionTitle("我的档案", identifier: "library-section-archive")
                    LazyVGrid(...)            // 原有网格，内容不变
                    if !store.encyclopedia.isEmpty {
                        sectionTitle("孕期百科", identifier: "library-section-encyclopedia")
                        EncyclopediaTopicGrid(catalog: store.encyclopedia, week: store.currentWeek) {
                            openTopic = $0
                        }
                    }
                    ForEach(LibraryCatalog.bannerCategories) { ... }   // 原有危险信号通栏，不变
```

3. 加在 `.navigationDestination(item: $openCategory)` 之后：

```swift
            .navigationDestination(item: $openTopic) { topic in
                EncyclopediaTopicView(topic: topic, store: store, agentStore: agentStore)
            }
            .navigationDestination(item: $openEntryID) { id in
                EncyclopediaEntryView(entryID: id, store: store, agentStore: agentStore)
            }
```

4. 加私有方法并改副标题：

```swift
    private func sectionTitle(_ text: String, identifier: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Color.aimTextPrimary)
            .padding(.top, AimMetrics.space8)
            .accessibilityIdentifier(identifier)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let week = store.currentWeek { parts.append("孕 \(week) 周") }
        if !store.encyclopedia.isEmpty { parts.append("百科 \(store.encyclopedia.entries.count) 条") }
        let mine = store.snapshot.records.count
        parts.append(mine == 0 ? "我的还没有内容" : "我的 \(mine) 条")
        return parts.joined(separator: " · ")
    }
```

- [ ] **Step 6: 「吃什么 · 饮食提示」改读百科**

`LibraryCategoryDetail.swift` 里把：

```swift
            if nutritionSection == .advice, let source = store.collections["nutrition"] {
                Section("Aim 自带的参考") {
                    ForEach(source.items) { item in
                        contentItemRow(item: item, collection: source)
                    }
                }
            }
```

替换为：

```swift
            // 自带的饮食参考来自孕期百科的「饮食营养」主题。
            if nutritionSection == .advice {
                let diet = store.encyclopedia.entries(inTopic: "diet", week: store.currentWeek)
                if !diet.isEmpty {
                    Section("孕期百科") {
                        ForEach(diet) { entry in
                            NavigationLink {
                                EncyclopediaEntryView(entryID: entry.id, store: store, agentStore: agentStore)
                            } label: {
                                EncyclopediaEntryRow(entry: entry, week: store.currentWeek)
                            }
                            .accessibilityIdentifier("encyclopedia-entry-\(entry.id)")
                            .listRowBackground(Color.aimSurface)
                        }
                    }
                }
            }
```

确认 `LibraryCategoryDetail` 里 `store` 的类型是 `LibraryStore`、`agentStore` 是非可选的 `AgentStore`（`sed -n 1,20p`）；如果 `agentStore` 是可选，改为 `if let agentStore` 包一层。

- [ ] **Step 7: 登记三个新文件并编译**

在 `project.pbxproj` 登记 `EncyclopediaSections.swift`（156）、`EncyclopediaTopicView.swift`（157）、`EncyclopediaEntryView.swift`（158）。

Run: `make ios-build 2>&1 | grep -E "error:|BUILD" | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: 跑 UI 用例**

前提：`make dev` 在跑，且 API 镜像已包含 Task 3 的内容（`curl -s 127.0.0.1:8100/api/v1/library/encyclopedia | head -c 200` 有内容）。

Run: `xcodebuild -project apps/ios/AimApp.xcodeproj -scheme AimApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath /tmp/aim-derived-data CODE_SIGNING_ALLOWED=NO test -only-testing:AimAppUITests/CoreJourneyUITests/testEncyclopediaTopicEntryAndAskAIM 2>&1 | grep -E "passed|failed|error:" | tail -5`
Expected: passed。再用同样的命令单独跑被修改的饮食提示用例（用 `grep -n "func test" apps/ios/AimApp/UITests/CoreJourneyUITests.swift` 找到它的名字），Expected: passed。

如果 UI 测试 target 名不是 `AimAppUITests`，先用 `xcodebuild -list -project apps/ios/AimApp.xcodeproj` 查。

- [ ] **Step 9: 提交**

```bash
git add apps/ios
git commit -m "feat(ios): 资料库新增「这周读什么」与孕期百科：主题页、条目详情、顺着条目问 AIM"
```

---

### Task 6: 端到端核对与收尾

**Files:**
- Modify: `content/README.md`（若不存在则在 `README.md` 的目录边界里补一行）——说明百科草稿与审核流程。

- [ ] **Step 1: 文档**

在 `content/` 说明处加：

```markdown
## 孕期百科（content/encyclopedia）

每个主题一个文件，格式见 `schema.json`。新内容一律 `review_status: draft`，只在本地栈
（`AIM_CONTENT_INCLUDE_DRAFTS=1`）可见；生产在 `compose.prod.yaml` 显式关闭草稿。
审核通过后把文件改为 `review_status: reviewed` 并填写 `reviewed_at`，提交即可随下次部署上线。
`services/api/tests/contract/content/test_encyclopedia_content.py` 守住格式、链接与孕周覆盖。
```

- [ ] **Step 2: 全量验证**

Run: `make verify`
Expected: lint、API 与 agent 测试、契约全部通过，`verify_repo.py` 无报错。

- [ ] **Step 3: 模拟器截图核对**

在 iPhone 18 Pro 模拟器上以孕 20 周左右的账号打开资料库：确认「这周读什么」有 3–5 张卡、「我的档案」六张卡不变、「孕期百科」六个主题卡；点进一个条目，推荐问题能把 AIM 打开并自动发出。截图留档。

- [ ] **Step 4: 提交**

```bash
git add content README.md
git commit -m "docs: 孕期百科的草稿与审核流程"
```
