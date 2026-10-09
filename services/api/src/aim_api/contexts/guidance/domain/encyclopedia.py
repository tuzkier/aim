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
    #: 能否进客户端首页的「这周读什么」。只针对部分人群或有前提条件的条目设为 False；
    #: 目录、主题页与孕周排序都不受影响——AIM 翻目录时仍要看得到它们。
    pick: bool = True

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
            "pick": self.pick,
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
            "related": [
                {"id": rid, "title": titles[rid]} for rid in entry.related if rid in titles
            ],
            "kind": entry.kind,
            "link": entry.link,
            "source": entry.source,
            "source_url": entry.source_url,
            "reviewed_at": entry.reviewed_at,
            "review_status": entry.review_status,
        }
