from __future__ import annotations

from dataclasses import dataclass
from datetime import date

import yaml

from aim_api.contexts.guidance.application.queries.get_guidance import CONTENT_ROOT


class UnknownCollection(Exception):
    """请求了白名单以外的集合。"""


# 白名单而不是「拼路径去读」——否则调用方能读到 content/ 下的任意目录。
# pregnancy-tasks 刻意不在其中：它由计划生成消费，不该被当成可浏览内容。
ALLOWED_COLLECTIONS = frozenset({"hangzhou", "preparation", "nutrition"})


@dataclass(frozen=True, slots=True)
class ContentItem:
    id: str
    title: str
    summary: str
    verification_url: str | None = None


@dataclass(frozen=True, slots=True)
class ContentCollection:
    id: str
    source: str
    source_url: str
    reviewed_at: date
    items: tuple[ContentItem, ...]


def execute(collection: str) -> ContentCollection:
    if collection not in ALLOWED_COLLECTIONS:
        raise UnknownCollection(f"unknown content collection: {collection}")

    content_dir = CONTENT_ROOT / collection
    documents = sorted(content_dir.glob("*.yaml")) if content_dir.is_dir() else []
    if not documents:
        raise UnknownCollection(f"content collection has no documents: {collection}")

    document = yaml.safe_load(documents[0].read_text(encoding="utf-8"))
    return ContentCollection(
        id=str(document["id"]),
        source=str(document["source"]),
        source_url=str(document["source_url"]),
        reviewed_at=date.fromisoformat(str(document["reviewed_at"])),
        items=tuple(
            ContentItem(
                id=str(item["id"]),
                title=str(item["title"]),
                summary=str(item["summary"]),
                verification_url=item.get("verification_url"),
            )
            for item in document["items"]
        ),
    )
