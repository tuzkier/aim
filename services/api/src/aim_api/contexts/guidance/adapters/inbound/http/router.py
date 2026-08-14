from __future__ import annotations

from fastapi import APIRouter, Query

from aim_api.contexts.guidance.application.queries.get_guidance import (
    GetGuidanceQuery,
    execute,
)

router = APIRouter(tags=["guidance"])


@router.get("/api/v1/guidance")
async def get_guidance_endpoint(week: int = Query(ge=0), region: str = Query(default="CN-ZJ-HZ")):
    return {"items": execute(GetGuidanceQuery(gestational_week=week, region=region))}
