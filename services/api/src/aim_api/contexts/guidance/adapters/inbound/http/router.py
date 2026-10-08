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
async def get_safety_rules_endpoint():
    """危险信号。不含个人数据，因此不要求登录——
    真出事的时候不该被登录态挡在外面。"""
    return {"items": execute_safety_rules()}


@router.get("/api/v1/content/{collection}")
async def get_content_collection_endpoint(collection: str):
    """可浏览的内容集合（办事指南、待产准备）。

    集合名走白名单，未知集合返回 404 而不是去磁盘上拼路径读取。
    """
    try:
        return execute_content_collection(collection)
    except UnknownCollection as error:
        raise NotFoundError(str(error)) from error
