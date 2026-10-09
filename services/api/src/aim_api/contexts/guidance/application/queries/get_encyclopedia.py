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
    pick = raw.get("pick", True)
    if not isinstance(pick, bool):
        raise ValueError(f"entry {entry_id} has non-boolean pick {pick!r}")

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
        pick=pick,
    )


@lru_cache(maxsize=1)
def get_encyclopedia() -> Encyclopedia:
    return load_encyclopedia(
        CONTENT_ROOT / ENCYCLOPEDIA_DIR,
        include_drafts=os.environ.get(INCLUDE_DRAFTS_ENV) == "1",
    )
