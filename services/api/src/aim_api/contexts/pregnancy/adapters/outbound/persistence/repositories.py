from __future__ import annotations

from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from aim_api.contexts.family.adapters.outbound.persistence.repositories import (
    SqlAlchemyFamilyRepository,
)
from aim_api.contexts.family.application.ports import PersistenceConflict
from aim_api.contexts.pregnancy.adapters.outbound.persistence.models import (
    PregnancyFactModel,
    PregnancyModel,
)
from aim_api.contexts.pregnancy.domain.fact import (
    FactRecordResult,
    FactSource,
    FactStatus,
    PregnancyFact,
    PregnancyFacts,
)
from aim_api.contexts.pregnancy.domain.pregnancy import Pregnancy, PregnancyStatus


class SqlAlchemyPregnancyRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def add_pregnancy(self, pregnancy: Pregnancy) -> None:
        self.session.add(
            PregnancyModel(
                id=pregnancy.id,
                family_id=pregnancy.family_id,
                due_date=pregnancy.due_date,
                created_by=pregnancy.created_by,
                status=pregnancy.status.value,
                created_at=pregnancy.created_at,
                updated_at=pregnancy.updated_at,
            )
        )

    async def get_pregnancy(self, pregnancy_id: UUID) -> Pregnancy | None:
        model = await self.session.get(PregnancyModel, pregnancy_id)
        if model is None:
            return None
        fact_models = (
            await self.session.scalars(
                select(PregnancyFactModel).where(PregnancyFactModel.pregnancy_id == pregnancy_id)
            )
        ).all()
        facts = PregnancyFacts.from_facts(_to_fact(fact) for fact in fact_models)
        return Pregnancy(
            id=model.id,
            family_id=model.family_id,
            due_date=model.due_date,
            created_by=model.created_by,
            status=PregnancyStatus(model.status),
            created_at=model.created_at,
            updated_at=model.updated_at,
            facts=facts,
            birth_date=model.birth_date,
            birth_revision=model.birth_revision,
        )

    async def save_due_date(self, pregnancy: Pregnancy) -> None:
        await self.session.execute(
            update(PregnancyModel)
            .where(PregnancyModel.id == pregnancy.id)
            .values(due_date=pregnancy.due_date, updated_at=pregnancy.updated_at)
        )

    async def get_first_pregnancy_for_family(self, family_id: UUID) -> Pregnancy | None:
        model = await self.session.scalar(
            select(PregnancyModel)
            .where(PregnancyModel.family_id == family_id)
            .order_by(PregnancyModel.created_at, PregnancyModel.id)
            .limit(1)
        )
        return await self.get_pregnancy(model.id) if model else None

    async def save_fact_result(
        self, pregnancy_id: UUID, result: FactRecordResult, recorded_by: UUID
    ) -> None:
        if not result.created:
            return
        fact = result.fact
        if fact.supersedes_fact_id is not None and fact.status is FactStatus.active:
            await self.session.execute(
                update(PregnancyFactModel)
                .where(PregnancyFactModel.id == fact.supersedes_fact_id)
                .values(status=FactStatus.superseded.value)
            )
        self.session.add(
            PregnancyFactModel(
                id=fact.id,
                pregnancy_id=pregnancy_id,
                fact_key=fact.key,
                value_json=fact.value,
                source=fact.source.value,
                priority=fact.priority,
                status=fact.status.value,
                observed_at=fact.observed_at,
                recorded_at=fact.recorded_at,
                recorded_by_account_id=recorded_by,
                supersedes_fact_id=fact.supersedes_fact_id,
            )
        )
        await self.session.execute(
            update(PregnancyModel)
            .where(PregnancyModel.id == pregnancy_id)
            .values(updated_at=fact.recorded_at)
        )


class SqlAlchemyPregnancyUnitOfWork:
    def __init__(self, session: AsyncSession) -> None:
        self.repository = SqlAlchemyPregnancyRepository(session)
        self.family_membership = SqlAlchemyFamilyRepository(session)
        self._session = session

    async def commit(self) -> None:
        try:
            await self._session.commit()
        except IntegrityError as error:
            await self._session.rollback()
            raise PersistenceConflict("pregnancy persistence constraint failed") from error

    async def rollback(self) -> None:
        await self._session.rollback()


def _to_fact(model: PregnancyFactModel) -> PregnancyFact:
    return PregnancyFact(
        id=model.id,
        key=model.fact_key,
        value=model.value_json,
        source=FactSource(model.source),
        observed_at=model.observed_at,
        recorded_at=model.recorded_at,
        status=FactStatus(model.status),
        supersedes_fact_id=model.supersedes_fact_id,
    )
