from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


class ApiError(Exception):
    status_code = 400
    code = "bad_request"

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message


class DatabaseUnavailable(ApiError):
    status_code = 503
    code = "database_unavailable"


class ForbiddenError(ApiError):
    status_code = 403
    code = "forbidden"


class NotFoundError(ApiError):
    status_code = 404
    code = "not_found"


class ConflictError(ApiError):
    status_code = 409
    code = "conflict"


class VersionConflictError(ConflictError):
    code = "task.version_conflict"


class ApprovalRequiredError(ConflictError):
    code = "approval_required"


class IdempotencyConflictError(ConflictError):
    code = "agent.idempotency_conflict"


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def handle_api_error(_: Request, error: ApiError) -> JSONResponse:
        return JSONResponse(
            status_code=error.status_code,
            content={"error": {"code": error.code, "message": error.message}},
        )
