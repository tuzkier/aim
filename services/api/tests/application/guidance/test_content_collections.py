from __future__ import annotations

import pytest

from aim_api.contexts.guidance.application.queries.get_content_collection import (
    UnknownCollection,
    execute,
)


class TestContentCollections:
    """办事指南与待产准备都只需要「一份条目清单」，共用一个接口即可。
    集合名走白名单——不能让调用方读到 content/ 下的任意目录。"""

    def test_serves_the_hangzhou_paperwork_collection(self):
        collection = execute("hangzhou")

        assert collection.items
        assert collection.source_url.startswith("http")

    def test_items_carry_id_title_and_summary(self):
        item = execute("hangzhou").items[0]

        assert item.id and item.title and item.summary

    def test_unknown_collection_is_rejected_rather_than_read_from_disk(self):
        with pytest.raises(UnknownCollection):
            execute("../../../etc")

    def test_a_collection_not_on_the_allowlist_is_rejected(self):
        with pytest.raises(UnknownCollection):
            execute("pregnancy-tasks")
