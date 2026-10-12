from datetime import UTC, datetime
from uuid import UUID, uuid4
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from aim_api.contexts.babies.adapters.outbound.persistence.models import BabyModel


class SqlAlchemyBabyRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def list_active(self, pregnancy_id: UUID, family_id: UUID) -> list[BabyModel]:
        return list((await self.session.scalars(select(BabyModel).where(
            BabyModel.pregnancy_id == pregnancy_id, BabyModel.family_id == family_id,
            BabyModel.archived_at.is_(None)).order_by(BabyModel.created_at, BabyModel.id))).all())

    async def get_active(self, baby_id: UUID, pregnancy_id: UUID, family_id: UUID) -> BabyModel | None:
        return await self.session.scalar(select(BabyModel).where(BabyModel.id == baby_id,
            BabyModel.pregnancy_id == pregnancy_id, BabyModel.family_id == family_id, BabyModel.archived_at.is_(None)))

    async def add(self, *, pregnancy_id: UUID, family_id: UUID, revision: UUID,
                  actor: UUID, name: str, birth_date, sex: str, weight: int | None) -> BabyModel:
        now = datetime.now(UTC)
        value = BabyModel(id=uuid4(), pregnancy_id=pregnancy_id, family_id=family_id,
            birth_revision=revision, name=name.strip() or "宝宝", birth_date=birth_date,
            sex=sex, birth_weight_grams=weight, created_by=actor, created_at=now,
            updated_at=now, archived_at=None)
        self.session.add(value)
        return value
