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


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
