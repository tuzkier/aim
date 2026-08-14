from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any
from uuid import UUID


class FactSource(StrEnum):
    doctor_confirmed = "doctor_confirmed"
    user_confirmed = "user_confirmed"
    machine_extracted = "machine_extracted"
    agent_inferred = "agent_inferred"
    general_knowledge = "general_knowledge"

    @property
    def priority(self) -> int:
        return {
            FactSource.doctor_confirmed: 5,
            FactSource.user_confirmed: 4,
            FactSource.machine_extracted: 3,
            FactSource.agent_inferred: 2,
            FactSource.general_knowledge: 1,
        }[self]


class FactStatus(StrEnum):
    active = "active"
    needs_verification = "needs_verification"
    superseded = "superseded"


@dataclass(frozen=True, slots=True)
class FactEvidence:
    id: UUID
    key: str
    value: Any
    source: FactSource
    observed_at: datetime


@dataclass(slots=True)
class PregnancyFact:
    id: UUID
    key: str
    value: Any
    source: FactSource
    observed_at: datetime
    recorded_at: datetime
    status: FactStatus = FactStatus.active
    supersedes_fact_id: UUID | None = None

    @property
    def priority(self) -> int:
        return self.source.priority


@dataclass(frozen=True, slots=True)
class FactRecordResult:
    fact: PregnancyFact
    needs_verification: bool
    created: bool = True


@dataclass(slots=True)
class PregnancyFacts:
    _facts: dict[UUID, PregnancyFact] = field(default_factory=dict)
    _active_by_key: dict[str, UUID] = field(default_factory=dict)

    @classmethod
    def from_facts(cls, facts) -> PregnancyFacts:
        collection = cls()
        for fact in facts:
            collection._facts[fact.id] = fact
            if fact.status is FactStatus.active:
                collection._active_by_key[fact.key] = fact.id
        return collection

    def record(self, evidence: FactEvidence, *, now: datetime | None = None) -> FactRecordResult:
        if not evidence.key.strip():
            raise ValueError("fact key cannot be empty")
        current = self._current(evidence.key)
        if current is not None and current.value == evidence.value:
            return FactRecordResult(fact=current, needs_verification=False, created=False)

        fact = PregnancyFact(
            id=evidence.id,
            key=evidence.key,
            value=evidence.value,
            source=evidence.source,
            observed_at=evidence.observed_at,
            recorded_at=now or datetime.now(UTC),
            supersedes_fact_id=current.id if current else None,
        )
        if current is None:
            self._facts[fact.id] = fact
            self._active_by_key[fact.key] = fact.id
            return FactRecordResult(fact=fact, needs_verification=False)
        if fact.priority > current.priority:
            current.status = FactStatus.superseded
            self._facts[fact.id] = fact
            self._active_by_key[fact.key] = fact.id
            return FactRecordResult(fact=fact, needs_verification=False)

        fact.status = FactStatus.needs_verification
        self._facts[fact.id] = fact
        return FactRecordResult(fact=fact, needs_verification=True)

    def active(self, key: str) -> PregnancyFact:
        return self._facts[self._active_by_key[key]]

    def all(self) -> tuple[PregnancyFact, ...]:
        return tuple(self._facts.values())

    def _current(self, key: str) -> PregnancyFact | None:
        fact_id = self._active_by_key.get(key)
        return self._facts.get(fact_id) if fact_id else None
