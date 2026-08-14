from __future__ import annotations

from fastapi import APIRouter, Request
from pydantic import BaseModel
from aim_api.platform.database.session import Database
from aim_api.platform.http.errors import DatabaseUnavailable

router = APIRouter(tags=["system"])


class HealthResponse(BaseModel):
    status: str
    database: str


@router.get("/api/v1/health", response_model=HealthResponse)
async def health(request: Request) -> HealthResponse:
    database: Database = request.app.state.database
    try:
        await database.ping()
    except Exception as error:  # database drivers expose different connection exceptions
        raise DatabaseUnavailable("PostgreSQL is not ready") from error
    return HealthResponse(status="ok", database="ready")
