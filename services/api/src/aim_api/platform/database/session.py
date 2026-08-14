from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """Base for outbound persistence models; domain objects never inherit from it."""


def _async_database_url(database_url: str) -> str:
    if not database_url.startswith("postgresql"):
        raise ValueError("DATABASE_URL must use PostgreSQL; SQLite is not supported")
    if "+psycopg" in database_url:
        return database_url.replace("+psycopg", "+asyncpg", 1)
    if database_url.startswith("postgresql://"):
        return database_url.replace("postgresql://", "postgresql+asyncpg://", 1)
    if "+asyncpg" in database_url:
        return database_url
    raise ValueError("DATABASE_URL must use the asyncpg or psycopg PostgreSQL driver")


@dataclass(slots=True)
class Database:
    engine: AsyncEngine
    session_factory: async_sessionmaker[AsyncSession]

    async def ping(self) -> None:
        async with self.engine.connect() as connection:
            await connection.execute(text("SELECT 1"))

    def session(self) -> AsyncSession:
        return self.session_factory()

    async def dispose(self) -> None:
        await self.engine.dispose()


def create_database(database_url: str) -> Database:
    engine = create_async_engine(
        _async_database_url(database_url),
        pool_pre_ping=True,
    )
    return Database(
        engine=engine, session_factory=async_sessionmaker(engine, expire_on_commit=False)
    )
