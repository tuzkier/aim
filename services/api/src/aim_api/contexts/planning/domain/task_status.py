from __future__ import annotations

from enum import StrEnum


class TaskStatus(StrEnum):
    todo = "todo"
    scheduled = "scheduled"
    done = "done"
    cancelled = "cancelled"


class TaskLifecycleError(Exception):
    code = "task.invalid_transition"


class InvalidTaskTransition(TaskLifecycleError):
    pass


class TaskVersionConflict(TaskLifecycleError):
    code = "task.version_conflict"


class TaskAssignmentError(TaskLifecycleError):
    code = "task.invalid_assignee"
