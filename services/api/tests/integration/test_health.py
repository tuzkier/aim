"""HTTP-level health checks against the configured PostgreSQL service."""

from __future__ import annotations

from fastapi.testclient import TestClient

from aim_api.bootstrap import create_app
from aim_api.platform.config.settings import get_settings
from aim_api.platform.database.session import create_database


def test_health_reports_database_ready() -> None:
    settings = get_settings()
    assert settings.database_url.startswith("postgresql")

    with TestClient(create_app(settings=settings)) as client:
        response = client.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "database": "ready"}


def test_database_factory_rejects_sqlite_fallback() -> None:
    try:
        create_database("sqlite+aiosqlite:///./should-not-exist.db")
    except ValueError as error:
        assert "PostgreSQL" in str(error)
    else:
        raise AssertionError("SQLite must never be used as a silent test fallback")
