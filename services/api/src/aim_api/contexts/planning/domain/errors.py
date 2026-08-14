from __future__ import annotations


class PlanningDomainError(Exception):
    code = "planning.domain_error"


class PlanningAccessDenied(PlanningDomainError):
    code = "planning.access_denied"


class PlanNotFound(PlanningDomainError):
    code = "planning.plan_not_found"


class TaskNotFound(PlanningDomainError):
    code = "task.not_found"


class TaskChangeNotFound(PlanningDomainError):
    code = "task.change_not_found"
