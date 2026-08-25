from __future__ import annotations

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Environment-backed settings with PostgreSQL as the only supported database."""

    model_config = SettingsConfigDict(
        case_sensitive=False,
        env_file=(".env", "../../.env"),
        extra="ignore",
    )

    database_url: str = Field(
        default="postgresql+asyncpg://aim:aim@localhost:5432/aim",
        validation_alias="DATABASE_URL",
    )
    api_host: str = Field(default="0.0.0.0", validation_alias="API_HOST")
    api_port: int = Field(default=8000, validation_alias="API_PORT")
    otel_enabled: bool = Field(default=False, validation_alias="OTEL_ENABLED")
    auth_secret: str = Field(default="aim-development-secret", validation_alias="AUTH_SECRET")
    auth_token_ttl_seconds: int = Field(default=3600, validation_alias="AUTH_TOKEN_TTL_SECONDS")
    agent_service_secret: str = Field(
        default="aim-agent-development-secret", validation_alias="AGENT_SERVICE_SECRET"
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
