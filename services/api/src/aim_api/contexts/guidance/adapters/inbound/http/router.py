from __future__ import annotations

from fastapi import APIRouter, Query

from aim_api.contexts.guidance.application.queries.get_guidance import (
    GetGuidanceQuery,
    execute,
)
from aim_api.contexts.guidance.application.queries.get_content_collection import (
    UnknownCollection,
)
from aim_api.contexts.guidance.application.queries.get_content_collection import (
    execute as execute_content_collection,
)
from aim_api.contexts.guidance.application.queries.get_encyclopedia import get_encyclopedia
from aim_api.contexts.guidance.application.queries.get_safety_rules import (
    execute as execute_safety_rules,
)
from aim_api.platform.http.errors import NotFoundError

from aim_api.contexts.guidance.application.queries import get_weekly_content

router = APIRouter(tags=["guidance"])


@router.get("/api/v1/content/weekly")
async def get_weekly_content_endpoint():
    """第 4–42 周的孕周内容。公开内容，不需要登录。"""
    return get_weekly_content.execute()


@router.get("/api/v1/guidance")
async def get_guidance_endpoint(week: int = Query(ge=0), region: str = Query(default="CN-ZJ-HZ")):
    return {"items": execute(GetGuidanceQuery(gestational_week=week, region=region))}


@router.get("/api/v1/safety-rules")
async def get_safety_rules_endpoint(week: int | None = Query(default=None, ge=0, le=45)):
    """危险信号。不含个人数据，因此不要求登录——
    真出事的时候不该被登录态挡在外面。

    week 可选：传了只返回该孕周适用的条目；不传返回全部，兼容旧版 App。"""
    return {"items": execute_safety_rules(week)}


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


@router.get("/api/v1/content/{collection}")
async def get_content_collection_endpoint(collection: str):
    """可浏览的内容集合（办事指南、待产准备）。

    集合名走白名单，未知集合返回 404 而不是去磁盘上拼路径读取。
    """
    try:
        return execute_content_collection(collection)
    except UnknownCollection as error:
        raise NotFoundError(str(error)) from error
