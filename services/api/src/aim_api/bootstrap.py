"""Composition root for the FastAPI business service."""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import TYPE_CHECKING

from fastapi import FastAPI

from aim_api.composition.family.router import router as family_composition_router
from aim_api.composition.today.router import router as today_router
from aim_api.composition.postpartum.router import router as postpartum_router
from aim_api.contexts.agent_access.adapters.inbound.http.operation_undo import (
    router as agent_operations_router,
)
from aim_api.contexts.agent_access.adapters.inbound.http.router import router as agent_tools_router
from aim_api.contexts.agent_access.adapters.inbound.http.sessions_router import (
    router as agent_sessions_router,
)
from aim_api.contexts.family.adapters.inbound.http.router import router as family_router
from aim_api.contexts.guidance.adapters.inbound.http.router import router as guidance_router
from aim_api.contexts.guidance.application.queries.get_encyclopedia import get_encyclopedia
from aim_api.contexts.identity.adapters.inbound.http.router import router as identity_router
from aim_api.contexts.planning.adapters.inbound.http.router import router as planning_router
from aim_api.contexts.pregnancy.adapters.inbound.http.router import router as pregnancy_router
from aim_api.contexts.records.adapters.inbound.http.attachments_router import (
    router as attachments_router,
)
from aim_api.contexts.records.adapters.inbound.http.router import router as records_router
from aim_api.platform.config.settings import Settings, get_settings
from aim_api.platform.database.session import Database, create_database
from aim_api.platform.http.errors import register_error_handlers
from aim_api.platform.http.health import router as health_router

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


def _configure_observability(app: FastAPI, database: Database, settings: Settings) -> None:
    """Attach optional OpenTelemetry instrumentation at the composition root."""

    if not settings.otel_enabled:
        return

    try:
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
        from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
    except ImportError:
        # Instrumentation packages are optional at runtime; the hook remains explicit so
        # production can enable them without leaking observability concerns into domain code.
        return

    FastAPIInstrumentor.instrument_app(app)
    SQLAlchemyInstrumentor().instrument(engine=database.engine.sync_engine)


def create_app(*, settings: Settings | None = None, database: Database | None = None) -> FastAPI:
    """Build an app with explicit infrastructure dependencies."""

    resolved_settings = settings or get_settings()
    # 百科内容有问题时让进程起不来，而不是等第一个请求才 500。
    get_encyclopedia()
    resolved_database = database or create_database(resolved_settings.database_url)

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        try:
            yield
        finally:
            if database is None:
                await resolved_database.dispose()

    app = FastAPI(
        title="Aim Business API",
        version="0.1.0",
        docs_url="/api/docs",
        openapi_url="/api/openapi.json",
        lifespan=lifespan,
    )
    app.state.settings = resolved_settings
    app.state.database = resolved_database
    register_error_handlers(app)
    app.include_router(health_router)
    app.include_router(identity_router)
    app.include_router(family_router)
    app.include_router(pregnancy_router)
    app.include_router(records_router)
    app.include_router(planning_router)
    # 具体内容地址必须先于 guidance 的 /content/{collection} 通配路由。
    app.include_router(postpartum_router)
    app.include_router(guidance_router)
    app.include_router(today_router)
    app.include_router(agent_tools_router)
    app.include_router(agent_sessions_router)
    app.include_router(agent_operations_router)
    app.include_router(attachments_router)
    app.include_router(family_composition_router)
    _configure_observability(app, resolved_database, resolved_settings)
    return app
