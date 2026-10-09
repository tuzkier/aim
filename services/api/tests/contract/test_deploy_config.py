from __future__ import annotations

from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[4]


class _ComposeLoader(yaml.SafeLoader):
    """认得 compose 的合并标签（`!override`、`!reset`），按普通节点读出。"""


def _construct_tagged(loader: yaml.SafeLoader, node: yaml.Node):
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node)
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node)
    return loader.construct_scalar(node)


for _tag in ("!override", "!reset"):
    _ComposeLoader.add_constructor(_tag, _construct_tagged)


def test_production_never_serves_draft_content() -> None:
    """生产编排叠加在本地编排之上，本地打开的草稿开关会被继承——必须显式关掉。"""
    text = (ROOT / "infrastructure/compose/compose.prod.yaml").read_text(encoding="utf-8")
    prod = yaml.load(text, Loader=_ComposeLoader)  # noqa: S506 — SafeLoader 子类
    assert prod["services"]["api"]["environment"]["AIM_CONTENT_INCLUDE_DRAFTS"] == "0"
