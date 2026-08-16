from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from aim_api.contexts.planning.domain.task import ActorType, Task, TaskSourceType
from aim_api.contexts.planning.domain.task_status import (
    InvalidTaskTransition,
    TaskStatus,
    TaskVersionConflict,
)


def _task() -> Task:
    now = datetime(2026, 8, 14, tzinfo=UTC)
    return Task.create(
        task_id=uuid4(),
        plan_id=uuid4(),
        pregnancy_id=uuid4(),
        title="预约系统超声",
        source_type=TaskSourceType.template,
        source_id="week-18-ultrasound",
        changed_by_actor_type=ActorType.account,
        changed_by_actor_id=uuid4(),
        now=now,
    )


def test_task_lifecycle_records_versions_and_allows_restore() -> None:
    task = _task()
    scheduled_for = datetime(2026, 8, 19, 9, 30, tzinfo=UTC)

    scheduled_change = task.schedule(scheduled_for, expected_version=1)
    assert task.status is TaskStatus.scheduled
    assert task.version == 2
    assert scheduled_change.version_after == 2

    completed_change = task.complete(expected_version=2)
    assert task.status is TaskStatus.done
    assert completed_change.version_after == 3

    restored_change = task.restore(expected_version=3)
    assert task.status is TaskStatus.todo
    assert restored_change.version_after == 4


def test_invalid_transition_and_stale_version_are_rejected() -> None:
    task = _task()
    task.complete(expected_version=1)

    with pytest.raises(InvalidTaskTransition):
        task.complete(expected_version=2)
    with pytest.raises(TaskVersionConflict):
        task.schedule(datetime(2026, 8, 20, tzinfo=UTC), expected_version=1)


def test_task_keeps_source_and_actor_provenance() -> None:
    task = _task()

    assert task.source_type is TaskSourceType.template
    assert task.source_id == "week-18-ultrasound"
    assert task.changed_by_actor_type is ActorType.account
    assert task.changed_by_actor_id is not None


def test_task_can_be_sourced_from_a_record() -> None:
    assert TaskSourceType.record.value == "record"
