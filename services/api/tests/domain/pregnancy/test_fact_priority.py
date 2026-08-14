from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

from aim_api.contexts.pregnancy.domain.fact import (
    FactEvidence,
    FactSource,
    FactStatus,
    PregnancyFacts,
)


def test_doctor_confirmed_fact_has_highest_priority() -> None:
    facts = PregnancyFacts()
    observed_at = datetime(2026, 8, 14, tzinfo=UTC)
    first = facts.record(
        FactEvidence(uuid4(), "blood_type", "A", FactSource.agent_inferred, observed_at)
    )
    assert first.fact.status is FactStatus.active

    doctor = facts.record(
        FactEvidence(uuid4(), "blood_type", "B", FactSource.doctor_confirmed, observed_at)
    )
    assert doctor.fact.status is FactStatus.active
    assert facts.active("blood_type").value == "B"


def test_lower_priority_conflict_never_silently_overwrites_high_priority_fact() -> None:
    facts = PregnancyFacts()
    observed_at = datetime(2026, 8, 14, tzinfo=UTC)
    facts.record(
        FactEvidence(uuid4(), "due_date", "2026-09-25", FactSource.doctor_confirmed, observed_at)
    )

    result = facts.record(
        FactEvidence(uuid4(), "due_date", "2026-10-02", FactSource.agent_inferred, observed_at)
    )

    assert result.fact.status is FactStatus.needs_verification
    assert result.needs_verification is True
    assert facts.active("due_date").value == "2026-09-25"


def test_same_value_from_lower_source_is_idempotent() -> None:
    facts = PregnancyFacts()
    observed_at = datetime(2026, 8, 14, tzinfo=UTC)
    facts.record(FactEvidence(uuid4(), "singleton", True, FactSource.user_confirmed, observed_at))
    result = facts.record(
        FactEvidence(uuid4(), "singleton", True, FactSource.machine_extracted, observed_at)
    )

    assert result.fact.status is FactStatus.active
    assert result.needs_verification is False
